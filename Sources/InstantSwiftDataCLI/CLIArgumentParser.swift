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
  case auth(CLIExamplesAuthLeafInvocation)
  case appBuilder(CLIExamplesAppBuilderLeafInvocation)
  case chat(CLIExamplesChatLeafInvocation)
  case counters(CLIExamplesCountersLeafInvocation)
  case microblog(CLIExamplesMicroblogLeafInvocation)
  case mobileChat(CLIExamplesMobileChatLeafInvocation)
  case reactions(CLIExamplesReactionsLeafInvocation)
  case typingIndicator(CLIExamplesTypingIndicatorLeafInvocation)
  case avatarStack(CLIExamplesAvatarStackLeafInvocation)
  case cursors(CLIExamplesCursorsLeafInvocation)
  case customCursors(CLIExamplesCursorsLeafInvocation)
  case mergeTileGame(CLIExamplesMergeTileGameLeafInvocation)
  case stroopwafel(CLIExamplesStroopwafelLeafInvocation)
  case syncUps(CLIExamplesSyncUpsLeafInvocation)
  case reminders(CLIExamplesRemindersLeafInvocation)
  case todoLinks(CLIExamplesTodoLinksLeafInvocation)
  case unknown(String, arguments: [String])
}

public struct CLIExamplesTodosInvocation: Equatable, Sendable {
  public var command: CLIExamplesTodosCommand?
  public var arguments: [String]
  public var leaf: CLIExamplesTodosLeafInvocation?

  public init(
    command: CLIExamplesTodosCommand?,
    arguments: [String],
    leaf: CLIExamplesTodosLeafInvocation? = nil
  ) {
    self.command = command
    self.arguments = arguments
    self.leaf = leaf
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

public enum CLIExamplesTodosLeafInvocation: Equatable, Sendable {
  case seed
  case add(text: String)
  case list(CLITodosQueryInvocation)
  case watch(CLIExamplesTodosWatchInvocation)
  case complete(todoID: String)
  case update(todoID: String, text: String)
  case delete(todoID: String)
  case reset
  case refresh(CLITodosQueryInvocation)
  case unknown(String)
}

public struct CLIExamplesTodosWatchInvocation: Equatable, Sendable {
  public var query: CLITodosQueryInvocation
  public var eventCount: Int

  public init(query: CLITodosQueryInvocation = CLITodosQueryInvocation(), eventCount: Int = 1) {
    self.query = query
    self.eventCount = eventCount
  }
}

public enum CLIExamplesTodosUsage {
  public static let todos =
    "Usage: instant-swift-data examples todos <add|seed|list|watch|complete|update|delete|reset|refresh>"
  public static let seed =
    "Usage: instant-swift-data examples todos seed [--json|--jsonl]"
  public static let add =
    #"Usage: instant-swift-data examples todos add "todo text""#
  public static let listCommand = "instant-swift-data examples todos list"
  public static let list =
    "\(listCommand) [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt]"
  public static let watchCommand = "instant-swift-data examples todos watch"
  public static let watch =
    "\(watchCommand) [--events 1] [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt]"
  public static let complete =
    "Usage: instant-swift-data examples todos complete <todo-id>"
  public static let update =
    #"Usage: instant-swift-data examples todos update <todo-id> "new text""#
  public static let delete =
    "Usage: instant-swift-data examples todos delete <todo-id>"
  public static let reset =
    "Usage: instant-swift-data examples todos reset [--json|--jsonl]"
}

public enum CLIExamplesTodosArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownListOption(String, usage: String)
  case unknownWatchOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesAuthLeafInvocation: Equatable, Sendable {
  case sendCode(email: String)
  case verifyCode(email: String, code: String)
  case status
  case watch(CLIExamplesAuthWatchInvocation)
  case signOut(CLIExamplesAuthSignOutInvocation)
  case unknown(String)
}

public struct CLIExamplesAuthWatchInvocation: Equatable, Sendable {
  public var eventCount: Int

  public init(eventCount: Int = 1) {
    self.eventCount = eventCount
  }
}

public struct CLIExamplesAuthSignOutInvocation: Equatable, Sendable {
  public var invalidateToken: Bool

  public init(invalidateToken: Bool = true) {
    self.invalidateToken = invalidateToken
  }
}

public enum CLIExamplesAuthUsage {
  public static let auth = """
    Usage: instant-swift-data examples auth <send-code|verify-code|status|watch|sign-out>
      instant-swift-data examples auth send-code <email> [--json|--jsonl]
      instant-swift-data examples auth verify-code <email> <code> [--json|--jsonl]
      instant-swift-data examples auth status [--json|--jsonl]
      instant-swift-data examples auth watch [--events 1] [--json|--jsonl]
      instant-swift-data examples auth sign-out [--skip-token-invalidation] [--json|--jsonl]
    """
  public static let sendCode =
    "Usage: instant-swift-data examples auth send-code <email> [--json|--jsonl]"
  public static let verifyCode =
    "Usage: instant-swift-data examples auth verify-code <email> <code> [--json|--jsonl]"
  public static let status =
    "Usage: instant-swift-data examples auth status [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples auth watch [--events 1] [--json|--jsonl]"
  public static let signOut =
    "Usage: instant-swift-data examples auth sign-out [--skip-token-invalidation] [--json|--jsonl]"
}

public enum CLIExamplesAuthArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case invalidEventCount(String, usageCommand: String)
  case missingValue(option: String, usage: String)
  case unknownOption(domain: String, option: String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesAppBuilderLeafInvocation: Equatable, Sendable {
  case generate(CLIExamplesAppBuilderGenerateInvocation)
  case list
  case show(buildID: String)
  case append(CLIExamplesAppBuilderAppendInvocation)
  case finish(buildID: String)
  case reset
  case unknown(String)
}

public struct CLIExamplesAppBuilderGenerateInvocation: Equatable, Sendable {
  public var prompt: String
  public var orgID: String

  public init(prompt: String, orgID: String) {
    self.prompt = prompt
    self.orgID = orgID
  }
}

public struct CLIExamplesAppBuilderAppendInvocation: Equatable, Sendable {
  public var buildID: String
  public var code: String?
  public var reasoning: String?
  public var isPreviewable: Bool?

  public init(
    buildID: String,
    code: String? = nil,
    reasoning: String? = nil,
    isPreviewable: Bool? = nil
  ) {
    self.buildID = buildID
    self.code = code
    self.reasoning = reasoning
    self.isPreviewable = isPreviewable
  }
}

public enum CLIExamplesAppBuilderUsage {
  public static let appBuilder = """
    Usage: instant-swift-data examples app-builder <generate|list|show|append|finish|reset>
      instant-swift-data examples app-builder generate "prompt" [--org-id org] [--json|--jsonl]
      instant-swift-data examples app-builder list [--json|--jsonl]
      instant-swift-data examples app-builder show <build-id> [--json|--jsonl]
      instant-swift-data examples app-builder append <build-id> [--code text] [--reasoning text] [--previewable true|false] [--json|--jsonl]
      instant-swift-data examples app-builder finish <build-id> [--json|--jsonl]
      instant-swift-data examples app-builder reset [--json|--jsonl]
    """
  public static let generate =
    #"Usage: instant-swift-data examples app-builder generate "prompt" [--org-id org] [--json|--jsonl]"#
  public static let list =
    "Usage: instant-swift-data examples app-builder list [--json|--jsonl]"
  public static let show =
    "Usage: instant-swift-data examples app-builder show <build-id> [--json|--jsonl]"
  public static let append =
    "Usage: instant-swift-data examples app-builder append <build-id> [--code text] [--reasoning text] [--previewable true|false] [--json|--jsonl]"
  public static let finish =
    "Usage: instant-swift-data examples app-builder finish <build-id> [--json|--jsonl]"
  public static let reset =
    "Usage: instant-swift-data examples app-builder reset [--json|--jsonl]"
}

public enum CLIExamplesAppBuilderArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case missingValue(option: String, usage: String)
  case unknownOption(option: String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesTodoLinksLeafInvocation: Equatable, Sendable {
  case seed
  case list
  case nested
  case unlink
  case unknown(String)
}

public enum CLIExamplesTodoLinksUsage {
  public static let todoLinks = """
    Usage: instant-swift-data examples todo-links <seed|list|nested|unlink>
      instant-swift-data examples todo-links seed [--json|--jsonl]
      instant-swift-data examples todo-links list [--json|--jsonl]
      instant-swift-data examples todo-links nested [--json|--jsonl]
      instant-swift-data examples todo-links unlink [--json|--jsonl]
    """
  public static let seed =
    "Usage: instant-swift-data examples todo-links seed [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples todo-links list [--json|--jsonl]"
  public static let nested =
    "Usage: instant-swift-data examples todo-links nested [--json|--jsonl]"
  public static let unlink =
    "Usage: instant-swift-data examples todo-links unlink [--json|--jsonl]"
}

public enum CLIExamplesTodoLinksArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesCountersLeafInvocation: Equatable, Sendable {
  case seed
  case add(count: Int)
  case list
  case increment(counterID: String)
  case decrement(counterID: String)
  case delete(counterID: String)
  case unknown(String)
}

public enum CLIExamplesCountersUsage {
  public static let counters = """
    Usage: instant-swift-data examples counters <seed|add|list|increment|decrement|delete>
      instant-swift-data examples counters seed [--json|--jsonl]
      instant-swift-data examples counters add [--count n] [--json|--jsonl]
      instant-swift-data examples counters list [--json|--jsonl]
      instant-swift-data examples counters increment <counter-id> [--json|--jsonl]
      instant-swift-data examples counters decrement <counter-id> [--json|--jsonl]
      instant-swift-data examples counters delete <counter-id> [--json|--jsonl]
    """
  public static let seed =
    "Usage: instant-swift-data examples counters seed [--json|--jsonl]"
  public static let add =
    "Usage: instant-swift-data examples counters add [--count n] [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples counters list [--json|--jsonl]"
  public static let increment =
    "Usage: instant-swift-data examples counters increment <counter-id> [--json|--jsonl]"
  public static let decrement =
    "Usage: instant-swift-data examples counters decrement <counter-id> [--json|--jsonl]"
  public static let delete =
    "Usage: instant-swift-data examples counters delete <counter-id> [--json|--jsonl]"
}

public enum CLIExamplesCountersArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesChatLeafInvocation: Equatable, Sendable {
  case seed
  case channels
  case messages(channelID: String?)
  case post(CLIExamplesChatPostInvocation)
  case reset
  case unknown(String)
}

public struct CLIExamplesChatPostInvocation: Equatable, Sendable {
  public var channelID: String
  public var text: String
  public var authorName: String?

  public init(channelID: String, text: String, authorName: String? = nil) {
    self.channelID = channelID
    self.text = text
    self.authorName = authorName
  }
}

public enum CLIExamplesChatUsage {
  public static let chat = """
    Usage: instant-swift-data examples chat <seed|channels|messages|post|reset>
      instant-swift-data examples chat seed [--json|--jsonl]
      instant-swift-data examples chat channels [--json|--jsonl]
      instant-swift-data examples chat messages [channel-id] [--json|--jsonl]
      instant-swift-data examples chat post <channel-id> "message text" [--author name] [--json|--jsonl]
      instant-swift-data examples chat reset [--json|--jsonl]
    """
  public static let seed =
    "Usage: instant-swift-data examples chat seed [--json|--jsonl]"
  public static let channels =
    "Usage: instant-swift-data examples chat channels [--json|--jsonl]"
  public static let messages =
    "Usage: instant-swift-data examples chat messages [channel-id] [--json|--jsonl]"
  public static let post =
    #"Usage: instant-swift-data examples chat post <channel-id> "message text" [--author name] [--json|--jsonl]"#
  public static let reset =
    "Usage: instant-swift-data examples chat reset [--json|--jsonl]"
}

public enum CLIExamplesChatArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownPostOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesMicroblogLeafInvocation: Equatable, Sendable {
  case seed
  case feed
  case profiles
  case profile(userID: String?)
  case setupProfile(displayName: String, handle: String)
  case post(CLIExamplesMicroblogPostInvocation)
  case like(postID: String)
  case unlike(postID: String)
  case deletePost(postID: String)
  case reset
  case unknown(String)
}

public struct CLIExamplesMicroblogPostInvocation: Equatable, Sendable {
  public var content: String
  public var color: String

  public init(content: String, color: String = "bg-blue-100") {
    self.content = content
    self.color = color
  }
}

public enum CLIExamplesMicroblogUsage {
  public static let microblog = """
    Usage: instant-swift-data examples microblog <seed|feed|profiles|profile|setup-profile|post|like|unlike|delete-post|reset>
      instant-swift-data examples microblog seed [--json|--jsonl]
      instant-swift-data examples microblog feed [--json|--jsonl]
      instant-swift-data examples microblog profiles [--json|--jsonl]
      instant-swift-data examples microblog profile [user-id] [--json|--jsonl]
      instant-swift-data examples microblog setup-profile "Display Name" <handle> [--json|--jsonl]
      instant-swift-data examples microblog post "content" [--color color] [--json|--jsonl]
      instant-swift-data examples microblog like <post-id> [--json|--jsonl]
      instant-swift-data examples microblog unlike <post-id> [--json|--jsonl]
      instant-swift-data examples microblog delete-post <post-id> [--json|--jsonl]
      instant-swift-data examples microblog reset [--json|--jsonl]
    """
  public static let seed =
    "Usage: instant-swift-data examples microblog seed [--json|--jsonl]"
  public static let feed =
    "Usage: instant-swift-data examples microblog feed [--json|--jsonl]"
  public static let profiles =
    "Usage: instant-swift-data examples microblog profiles [--json|--jsonl]"
  public static let profile =
    "Usage: instant-swift-data examples microblog profile [user-id] [--json|--jsonl]"
  public static let setupProfile =
    #"Usage: instant-swift-data examples microblog setup-profile "Display Name" <handle> [--json|--jsonl]"#
  public static let post =
    #"Usage: instant-swift-data examples microblog post "content" [--color color] [--json|--jsonl]"#
  public static let like =
    "Usage: instant-swift-data examples microblog like <post-id> [--json|--jsonl]"
  public static let unlike =
    "Usage: instant-swift-data examples microblog unlike <post-id> [--json|--jsonl]"
  public static let deletePost =
    "Usage: instant-swift-data examples microblog delete-post <post-id> [--json|--jsonl]"
  public static let reset =
    "Usage: instant-swift-data examples microblog reset [--json|--jsonl]"
}

public enum CLIExamplesMicroblogArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownPostOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesMobileChatLeafInvocation: Equatable, Sendable {
  case seed
  case channels
  case messages(channelID: String?)
  case profiles
  case profile(userID: String?)
  case setupProfile(displayName: String)
  case send(CLIExamplesMobileChatSendInvocation)
  case join(channelID: String)
  case presence(channelID: String)
  case leave(channelID: String)
  case reset
  case unknown(String)
}

public struct CLIExamplesMobileChatSendInvocation: Equatable, Sendable {
  public var channelID: String
  public var content: String

  public init(channelID: String, content: String) {
    self.channelID = channelID
    self.content = content
  }
}

public enum CLIExamplesMobileChatUsage {
  public static let mobileChat = """
    Usage: instant-swift-data examples mobile-chat <seed|channels|messages|profiles|profile|setup-profile|send|join|presence|leave|reset>
      instant-swift-data examples mobile-chat seed [--json|--jsonl]
      instant-swift-data examples mobile-chat channels [--json|--jsonl]
      instant-swift-data examples mobile-chat messages [channel-id] [--json|--jsonl]
      instant-swift-data examples mobile-chat profiles [--json|--jsonl]
      instant-swift-data examples mobile-chat profile [user-id] [--json|--jsonl]
      instant-swift-data examples mobile-chat setup-profile "Display Name" [--json|--jsonl]
      instant-swift-data examples mobile-chat send <channel-id> "message text" [--json|--jsonl]
      instant-swift-data examples mobile-chat join <channel-id> [--json|--jsonl]
      instant-swift-data examples mobile-chat presence <channel-id> [--json|--jsonl]
      instant-swift-data examples mobile-chat leave <channel-id> [--json|--jsonl]
      instant-swift-data examples mobile-chat reset [--json|--jsonl]
    """
  public static let seed =
    "Usage: instant-swift-data examples mobile-chat seed [--json|--jsonl]"
  public static let channels =
    "Usage: instant-swift-data examples mobile-chat channels [--json|--jsonl]"
  public static let messages =
    "Usage: instant-swift-data examples mobile-chat messages [channel-id] [--json|--jsonl]"
  public static let profiles =
    "Usage: instant-swift-data examples mobile-chat profiles [--json|--jsonl]"
  public static let profile =
    "Usage: instant-swift-data examples mobile-chat profile [user-id] [--json|--jsonl]"
  public static let setupProfile =
    #"Usage: instant-swift-data examples mobile-chat setup-profile "Display Name" [--json|--jsonl]"#
  public static let send =
    #"Usage: instant-swift-data examples mobile-chat send <channel-id> "message text" [--json|--jsonl]"#
  public static let join =
    "Usage: instant-swift-data examples mobile-chat join <channel-id> [--json|--jsonl]"
  public static let presence =
    "Usage: instant-swift-data examples mobile-chat presence <channel-id> [--json|--jsonl]"
  public static let leave =
    "Usage: instant-swift-data examples mobile-chat leave <channel-id> [--json|--jsonl]"
  public static let reset =
    "Usage: instant-swift-data examples mobile-chat reset [--json|--jsonl]"
}

public enum CLIExamplesMobileChatArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownSendOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesStroopwafelLeafInvocation: Equatable, Sendable {
  case setupProfile(handle: String)
  case profile(userID: String?)
  case score(Int)
  case createRoom(code: String?)
  case rooms
  case room(code: String)
  case join(code: String)
  case ready(code: String, isReady: Bool)
  case kick(code: String, userID: String)
  case start(code: String)
  case games
  case game(gameID: String)
  case tap(gameID: String, color: String)
  case leave(code: String)
  case reset
  case unknown(String)
}

public enum CLIExamplesStroopwafelUsage {
  public static let stroopwafel = """
    Usage: instant-swift-data examples stroopwafel <setup-profile|profile|score|create-room|rooms|room|join|ready|unready|kick|start|games|game|tap|leave|reset>
      instant-swift-data examples stroopwafel setup-profile <handle> [--json|--jsonl]
      instant-swift-data examples stroopwafel profile [user-id] [--json|--jsonl]
      instant-swift-data examples stroopwafel score <score> [--json|--jsonl]
      instant-swift-data examples stroopwafel create-room [code] [--json|--jsonl]
      instant-swift-data examples stroopwafel rooms [--json|--jsonl]
      instant-swift-data examples stroopwafel room <code> [--json|--jsonl]
      instant-swift-data examples stroopwafel join <code> [--json|--jsonl]
      instant-swift-data examples stroopwafel ready <code> [--json|--jsonl]
      instant-swift-data examples stroopwafel unready <code> [--json|--jsonl]
      instant-swift-data examples stroopwafel kick <code> <user-id> [--json|--jsonl]
      instant-swift-data examples stroopwafel start <code> [--json|--jsonl]
      instant-swift-data examples stroopwafel games [--json|--jsonl]
      instant-swift-data examples stroopwafel game <game-id> [--json|--jsonl]
      instant-swift-data examples stroopwafel tap <game-id> <red|green|blue|yellow> [--json|--jsonl]
      instant-swift-data examples stroopwafel leave <code> [--json|--jsonl]
      instant-swift-data examples stroopwafel reset [--json|--jsonl]
    """
  public static let setupProfile =
    "Usage: instant-swift-data examples stroopwafel setup-profile <handle> [--json|--jsonl]"
  public static let profile =
    "Usage: instant-swift-data examples stroopwafel profile [user-id] [--json|--jsonl]"
  public static let score =
    "Usage: instant-swift-data examples stroopwafel score <score> [--json|--jsonl]"
  public static let createRoom =
    "Usage: instant-swift-data examples stroopwafel create-room [code] [--json|--jsonl]"
  public static let rooms =
    "Usage: instant-swift-data examples stroopwafel rooms [--json|--jsonl]"
  public static let room =
    "Usage: instant-swift-data examples stroopwafel room <code> [--json|--jsonl]"
  public static let join =
    "Usage: instant-swift-data examples stroopwafel join <code> [--json|--jsonl]"
  public static let ready =
    "Usage: instant-swift-data examples stroopwafel ready <code> [--json|--jsonl]"
  public static let unready =
    "Usage: instant-swift-data examples stroopwafel unready <code> [--json|--jsonl]"
  public static let kick =
    "Usage: instant-swift-data examples stroopwafel kick <code> <user-id> [--json|--jsonl]"
  public static let start =
    "Usage: instant-swift-data examples stroopwafel start <code> [--json|--jsonl]"
  public static let games =
    "Usage: instant-swift-data examples stroopwafel games [--json|--jsonl]"
  public static let game =
    "Usage: instant-swift-data examples stroopwafel game <game-id> [--json|--jsonl]"
  public static let tap =
    "Usage: instant-swift-data examples stroopwafel tap <game-id> <red|green|blue|yellow> [--json|--jsonl]"
  public static let leave =
    "Usage: instant-swift-data examples stroopwafel leave <code> [--json|--jsonl]"
  public static let reset =
    "Usage: instant-swift-data examples stroopwafel reset [--json|--jsonl]"
}

public enum CLIExamplesStroopwafelArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case invalidColor(String, usage: String)
  case invalidScore(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesReactionsLeafInvocation: Equatable, Sendable {
  case tap(CLIExamplesReactionsTapInvocation)
  case list(CLIExamplesReactionsListInvocation)
  case watch(CLIExamplesReactionsWatchInvocation)
  case unknown(String)
}

public struct CLIExamplesReactionsTapInvocation: Equatable, Sendable {
  public var name: String
  public var directionAngle: Double
  public var rotationAngle: Double
  public var userID: String?

  public init(
    name: String,
    directionAngle: Double = 0,
    rotationAngle: Double = 0,
    userID: String? = nil
  ) {
    self.name = name
    self.directionAngle = directionAngle
    self.rotationAngle = rotationAngle
    self.userID = userID
  }
}

public struct CLIExamplesReactionsListInvocation: Equatable, Sendable {
  public var limit: Int?

  public init(limit: Int? = nil) {
    self.limit = limit
  }
}

public struct CLIExamplesReactionsWatchInvocation: Equatable, Sendable {
  public var eventCount: Int

  public init(eventCount: Int = 1) {
    self.eventCount = eventCount
  }
}

public enum CLIExamplesReactionsUsage {
  public static let reactions = """
    Usage: instant-swift-data examples reactions <tap|list|watch>
      instant-swift-data examples reactions tap <fire|wave|confetti|heart> [--direction degrees] [--rotation degrees] [--user-id id] [--json|--jsonl]
      instant-swift-data examples reactions list [--limit n] [--json|--jsonl]
      instant-swift-data examples reactions watch [--events 1] [--json|--jsonl]
    """
  public static let tap =
    "Usage: instant-swift-data examples reactions tap <fire|wave|confetti|heart> [--direction degrees] [--rotation degrees] [--user-id id] [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples reactions list [--limit n] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples reactions watch [--events 1] [--json|--jsonl]"
}

public enum CLIExamplesReactionsArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case invalidReactionName(String, usage: String)
  case invalidAngle(String, usage: String)
  case unknownTapOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesTypingIndicatorLeafInvocation: Equatable, Sendable {
  case join(userID: String)
  case type(userID: String)
  case stop(userID: String)
  case list(CLIExamplesTypingIndicatorListInvocation)
  case watch(CLIExamplesTypingIndicatorWatchInvocation)
  case leave(userID: String)
  case unknown(String)
}

public struct CLIExamplesTypingIndicatorListInvocation: Equatable, Sendable {
  public var viewerUserID: String?

  public init(viewerUserID: String? = nil) {
    self.viewerUserID = viewerUserID
  }
}

public struct CLIExamplesTypingIndicatorWatchInvocation: Equatable, Sendable {
  public var eventCount: Int
  public var viewerUserID: String?

  public init(eventCount: Int = 1, viewerUserID: String? = nil) {
    self.eventCount = eventCount
    self.viewerUserID = viewerUserID
  }
}

public enum CLIExamplesTypingIndicatorUsage {
  public static let typingIndicator = """
    Usage: instant-swift-data examples typing-indicator <join|type|stop|list|watch|leave>
      instant-swift-data examples typing-indicator join <user-id> [--json|--jsonl]
      instant-swift-data examples typing-indicator type <user-id> [--json|--jsonl]
      instant-swift-data examples typing-indicator stop <user-id> [--json|--jsonl]
      instant-swift-data examples typing-indicator list [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples typing-indicator watch [--events 1] [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples typing-indicator leave <user-id> [--json|--jsonl]
    """
  public static let user =
    "Usage: instant-swift-data examples typing-indicator <join|type|stop|leave> <user-id> [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples typing-indicator list [--viewer-user-id id] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples typing-indicator watch [--events 1] [--viewer-user-id id] [--json|--jsonl]"
}

public enum CLIExamplesTypingIndicatorArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesAvatarStackLeafInvocation: Equatable, Sendable {
  case join(CLIExamplesAvatarStackJoinInvocation)
  case list(CLIExamplesAvatarStackListInvocation)
  case watch(CLIExamplesAvatarStackWatchInvocation)
  case leave(userID: String)
  case unknown(String)
}

public struct CLIExamplesAvatarStackJoinInvocation: Equatable, Sendable {
  public var userID: String
  public var name: String?

  public init(userID: String, name: String? = nil) {
    self.userID = userID
    self.name = name
  }
}

public struct CLIExamplesAvatarStackListInvocation: Equatable, Sendable {
  public var viewerUserID: String?

  public init(viewerUserID: String? = nil) {
    self.viewerUserID = viewerUserID
  }
}

public struct CLIExamplesAvatarStackWatchInvocation: Equatable, Sendable {
  public var eventCount: Int
  public var viewerUserID: String?

  public init(eventCount: Int = 1, viewerUserID: String? = nil) {
    self.eventCount = eventCount
    self.viewerUserID = viewerUserID
  }
}

public enum CLIExamplesAvatarStackUsage {
  public static let avatarStack = """
    Usage: instant-swift-data examples avatar-stack <join|list|watch|leave>
      instant-swift-data examples avatar-stack join <user-id> [--name name] [--json|--jsonl]
      instant-swift-data examples avatar-stack list [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples avatar-stack watch [--events 1] [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples avatar-stack leave <user-id> [--json|--jsonl]
    """
  public static let join =
    "Usage: instant-swift-data examples avatar-stack join <user-id> [--name name] [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples avatar-stack list [--viewer-user-id id] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples avatar-stack watch [--events 1] [--viewer-user-id id] [--json|--jsonl]"
  public static let leave =
    "Usage: instant-swift-data examples avatar-stack leave <user-id> [--json|--jsonl]"
}

public enum CLIExamplesAvatarStackArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesCursorsLeafInvocation: Equatable, Sendable {
  case move(CLIExamplesCursorsMoveInvocation)
  case list(CLIExamplesCursorsListInvocation)
  case watch(CLIExamplesCursorsWatchInvocation)
  case clear(userID: String)
  case leave(userID: String)
  case unknown(String)
}

public struct CLIExamplesCursorsMoveInvocation: Equatable, Sendable {
  public var userID: String
  public var x: Double
  public var y: Double
  public var xPercent: Double
  public var yPercent: Double
  public var color: String?
  public var name: String?

  public init(
    userID: String,
    x: Double,
    y: Double,
    xPercent: Double,
    yPercent: Double,
    color: String? = nil,
    name: String? = nil
  ) {
    self.userID = userID
    self.x = x
    self.y = y
    self.xPercent = xPercent
    self.yPercent = yPercent
    self.color = color
    self.name = name
  }
}

public struct CLIExamplesCursorsListInvocation: Equatable, Sendable {
  public var viewerUserID: String?

  public init(viewerUserID: String? = nil) {
    self.viewerUserID = viewerUserID
  }
}

public struct CLIExamplesCursorsWatchInvocation: Equatable, Sendable {
  public var eventCount: Int
  public var viewerUserID: String?

  public init(eventCount: Int = 1, viewerUserID: String? = nil) {
    self.eventCount = eventCount
    self.viewerUserID = viewerUserID
  }
}

public enum CLIExamplesCursorsUsage {
  public static let cursors = """
    Usage: instant-swift-data examples cursors <move|list|watch|clear|leave>
      instant-swift-data examples cursors move <user-id> --x n --y n --x-percent n --y-percent n [--color color] [--json|--jsonl]
      instant-swift-data examples cursors list [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples cursors watch [--events 1] [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples cursors clear <user-id> [--json|--jsonl]
      instant-swift-data examples cursors leave <user-id> [--json|--jsonl]
    """
  public static let move =
    "Usage: instant-swift-data examples cursors move <user-id> --x n --y n --x-percent n --y-percent n [--color color] [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples cursors list [--viewer-user-id id] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples cursors watch [--events 1] [--viewer-user-id id] [--json|--jsonl]"
  public static let user =
    "Usage: instant-swift-data examples cursors <clear|leave> <user-id> [--json|--jsonl]"
}

public enum CLIExamplesCustomCursorsUsage {
  public static let customCursors = """
    Usage: instant-swift-data examples custom-cursors <move|list|watch|clear|leave>
      instant-swift-data examples custom-cursors move <user-id> --x n --y n --x-percent n --y-percent n [--color color] [--name name] [--json|--jsonl]
      instant-swift-data examples custom-cursors list [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples custom-cursors watch [--events 1] [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples custom-cursors clear <user-id> [--json|--jsonl]
      instant-swift-data examples custom-cursors leave <user-id> [--json|--jsonl]
    """
  public static let move =
    "Usage: instant-swift-data examples custom-cursors move <user-id> --x n --y n --x-percent n --y-percent n [--color color] [--name name] [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples custom-cursors list [--viewer-user-id id] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples custom-cursors watch [--events 1] [--viewer-user-id id] [--json|--jsonl]"
  public static let user =
    "Usage: instant-swift-data examples custom-cursors <clear|leave> <user-id> [--json|--jsonl]"
}

public enum CLIExamplesCursorsArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesMergeTileGameLeafInvocation: Equatable, Sendable {
  case join(CLIExamplesMergeTileGameJoinInvocation)
  case tap(CLIExamplesMergeTileGameTapInvocation)
  case board(CLIExamplesMergeTileGameBoardInvocation)
  case watch(CLIExamplesMergeTileGameWatchInvocation)
  case reset
  case leave(userID: String)
  case unknown(String)
}

public struct CLIExamplesMergeTileGameJoinInvocation: Equatable, Sendable {
  public var userID: String
  public var color: String?

  public init(userID: String, color: String? = nil) {
    self.userID = userID
    self.color = color
  }
}

public struct CLIExamplesMergeTileGameTapInvocation: Equatable, Sendable {
  public var userID: String
  public var row: Int
  public var column: Int
  public var color: String?

  public init(userID: String, row: Int, column: Int, color: String? = nil) {
    self.userID = userID
    self.row = row
    self.column = column
    self.color = color
  }
}

public struct CLIExamplesMergeTileGameBoardInvocation: Equatable, Sendable {
  public var viewerUserID: String?

  public init(viewerUserID: String? = nil) {
    self.viewerUserID = viewerUserID
  }
}

public struct CLIExamplesMergeTileGameWatchInvocation: Equatable, Sendable {
  public var eventCount: Int
  public var viewerUserID: String?

  public init(eventCount: Int = 1, viewerUserID: String? = nil) {
    self.eventCount = eventCount
    self.viewerUserID = viewerUserID
  }
}

public enum CLIExamplesMergeTileGameUsage {
  public static let mergeTileGame = """
    Usage: instant-swift-data examples merge-tile-game <join|tap|board|watch|reset|leave>
      instant-swift-data examples merge-tile-game join <user-id> [--color color] [--json|--jsonl]
      instant-swift-data examples merge-tile-game tap <user-id> <row> <column> [--color color] [--json|--jsonl]
      instant-swift-data examples merge-tile-game board [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples merge-tile-game watch [--events 1] [--viewer-user-id id] [--json|--jsonl]
      instant-swift-data examples merge-tile-game reset [--json|--jsonl]
      instant-swift-data examples merge-tile-game leave <user-id> [--json|--jsonl]
    """
  public static let join =
    "Usage: instant-swift-data examples merge-tile-game join <user-id> [--color color] [--json|--jsonl]"
  public static let tap =
    "Usage: instant-swift-data examples merge-tile-game tap <user-id> <row> <column> [--color color] [--json|--jsonl]"
  public static let board =
    "Usage: instant-swift-data examples merge-tile-game board [--viewer-user-id id] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data examples merge-tile-game watch [--events 1] [--viewer-user-id id] [--json|--jsonl]"
  public static let reset =
    "Usage: instant-swift-data examples merge-tile-game reset [--json|--jsonl]"
  public static let leave =
    "Usage: instant-swift-data examples merge-tile-game leave <user-id> [--json|--jsonl]"
}

public enum CLIExamplesMergeTileGameArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesSyncUpsLeafInvocation: Equatable, Sendable {
  case seed
  case list(CLIExamplesSyncUpsListInvocation)
  case detail(syncUpID: String)
  case add(CLIExamplesSyncUpsAddInvocation)
  case update(CLIExamplesSyncUpsUpdateInvocation)
  case addAttendee(syncUpID: String, name: String)
  case record(syncUpID: String, transcript: String)
  case recordDemo(syncUpID: String)
  case delete(syncUpID: String)
  case deleteAttendee(attendeeID: String)
  case deleteMeeting(meetingID: String)
  case unknown(String)
}

public struct CLIExamplesSyncUpsListInvocation: Equatable, Sendable {
  public var event: String
  public var syncUpID: String?

  public init(event: String = "list", syncUpID: String? = nil) {
    self.event = event
    self.syncUpID = syncUpID
  }
}

public struct CLIExamplesSyncUpsAddInvocation: Equatable, Sendable {
  public var title: String
  public var seconds: Int
  public var theme: String
  public var attendeeNames: [String]

  public init(
    title: String,
    seconds: Int = 60 * 5,
    theme: String = "bubblegum",
    attendeeNames: [String]
  ) {
    self.title = title
    self.seconds = seconds
    self.theme = theme
    self.attendeeNames = attendeeNames
  }
}

public struct CLIExamplesSyncUpsUpdateInvocation: Equatable, Sendable {
  public var event: String
  public var syncUpID: String
  public var title: String?
  public var seconds: Int?
  public var theme: String?
  public var replacementAttendeeNames: [String]?

  public init(
    event: String,
    syncUpID: String,
    title: String? = nil,
    seconds: Int? = nil,
    theme: String? = nil,
    replacementAttendeeNames: [String]? = nil
  ) {
    self.event = event
    self.syncUpID = syncUpID
    self.title = title
    self.seconds = seconds
    self.theme = theme
    self.replacementAttendeeNames = replacementAttendeeNames
  }
}

public enum CLIExamplesSyncUpsUsage {
  public static let syncUps = """
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
  public static let seed =
    "Usage: instant-swift-data examples sync-ups seed [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples sync-ups list [--refresh] [--sync-up-id id] [--json|--jsonl]"
  public static let detail =
    "Usage: instant-swift-data examples sync-ups detail <sync-up-id> [--json|--jsonl]"
  public static let add =
    #"Usage: instant-swift-data examples sync-ups add "title" [--seconds n] [--theme theme] [--attendee name ...]"#
  public static let addAttendee =
    #"Usage: instant-swift-data examples sync-ups add-attendee <sync-up-id> "name""#
  public static let edit =
    #"Usage: instant-swift-data examples sync-ups edit <sync-up-id> [--title title] [--seconds n] [--theme theme] [--attendee name ...]"#
  public static let record =
    #"Usage: instant-swift-data examples sync-ups record <sync-up-id> [--transcript] "transcript""#
  public static let recordDemo =
    "Usage: instant-swift-data examples sync-ups record-demo <sync-up-id>"
  public static let recordTranscript =
    #"Usage: instant-swift-data examples sync-ups record <sync-up-id> --transcript "text""#
  public static let delete =
    "Usage: instant-swift-data examples sync-ups delete <sync-up-id>"
  public static let deleteAttendee =
    "Usage: instant-swift-data examples sync-ups delete-attendee <attendee-id>"
  public static let deleteMeeting =
    "Usage: instant-swift-data examples sync-ups delete-meeting <meeting-id>"
}

public enum CLIExamplesSyncUpsArgumentError: Error, Equatable, Sendable {
  case invalidArguments(String)
  case invalidTheme

  public var exitCode: Int32 { 64 }
}

public enum CLIExamplesRemindersLeafInvocation: Equatable, Sendable {
  case seed
  case list(CLIExamplesRemindersListInvocation)
  case stats
  case tags
  case addList(title: String)
  case renameList(listID: String, title: String)
  case add(CLIExamplesReminderAddInvocation)
  case update(CLIExamplesReminderUpdateInvocation)
  case complete(reminderID: String)
  case delete(reminderID: String)
  case deleteCompleted(listID: String?)
  case deleteList(listID: String)
  case addTag(reminderID: String, rawTag: String)
  case removeTag(reminderID: String, rawTag: String)
  case search(CLIExamplesRemindersSearchInvocation)
  case unknown(String)
}

public struct CLIExamplesRemindersListInvocation: Equatable, Sendable {
  public var event: String
  public var listID: String?
  public var includeCompleted: Bool
  public var flagged: Bool?
  public var scheduled: Bool
  public var today: Bool
  public var priorityRawValue: String?

  public init(
    event: String = "list",
    listID: String? = nil,
    includeCompleted: Bool = true,
    flagged: Bool? = nil,
    scheduled: Bool = false,
    today: Bool = false,
    priorityRawValue: String? = nil
  ) {
    self.event = event
    self.listID = listID
    self.includeCompleted = includeCompleted
    self.flagged = flagged
    self.scheduled = scheduled
    self.today = today
    self.priorityRawValue = priorityRawValue
  }
}

public struct CLIExamplesRemindersSearchInvocation: Equatable, Sendable {
  public var text: String
  public var listID: String?
  public var rawTag: String?
  public var includeCompleted: Bool
  public var flagged: Bool?
  public var scheduled: Bool
  public var today: Bool
  public var priorityRawValue: String?

  public init(
    text: String,
    listID: String? = nil,
    rawTag: String? = nil,
    includeCompleted: Bool = false,
    flagged: Bool? = nil,
    scheduled: Bool = false,
    today: Bool = false,
    priorityRawValue: String? = nil
  ) {
    self.text = text
    self.listID = listID
    self.rawTag = rawTag
    self.includeCompleted = includeCompleted
    self.flagged = flagged
    self.scheduled = scheduled
    self.today = today
    self.priorityRawValue = priorityRawValue
  }
}

public struct CLIExamplesReminderAddInvocation: Equatable, Sendable {
  public var listID: String
  public var title: String
  public var notes: String
  public var isFlagged: Bool
  public var dueDateRawValue: String?
  public var priorityRawValue: String?

  public init(
    listID: String,
    title: String,
    notes: String = "",
    isFlagged: Bool = false,
    dueDateRawValue: String? = nil,
    priorityRawValue: String? = nil
  ) {
    self.listID = listID
    self.title = title
    self.notes = notes
    self.isFlagged = isFlagged
    self.dueDateRawValue = dueDateRawValue
    self.priorityRawValue = priorityRawValue
  }
}

public struct CLIExamplesReminderUpdateInvocation: Equatable, Sendable {
  public var reminderID: String
  public var title: String?
  public var notes: String?
  public var isFlagged: Bool?
  public var dueDateRawValue: String?
  public var clearsDueDate: Bool
  public var priorityRawValue: String?
  public var clearsPriority: Bool

  public init(
    reminderID: String,
    title: String? = nil,
    notes: String? = nil,
    isFlagged: Bool? = nil,
    dueDateRawValue: String? = nil,
    clearsDueDate: Bool = false,
    priorityRawValue: String? = nil,
    clearsPriority: Bool = false
  ) {
    self.reminderID = reminderID
    self.title = title
    self.notes = notes
    self.isFlagged = isFlagged
    self.dueDateRawValue = dueDateRawValue
    self.clearsDueDate = clearsDueDate
    self.priorityRawValue = priorityRawValue
    self.clearsPriority = clearsPriority
  }
}

public enum CLIExamplesRemindersUsage {
  public static let priorityList = "low|medium|high"
  public static let reminders = """
    Usage: instant-swift-data examples reminders <seed|list|stats|tags|list-tags|search|add-list|rename-list|delete-list|add|update|complete|delete|delete-completed|add-tag|remove-tag>
      instant-swift-data examples reminders seed [--json|--jsonl]
      instant-swift-data examples reminders list [--refresh] [--list-id id] [--completed true|false] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(priorityList)] [--json|--jsonl]
      instant-swift-data examples reminders stats [--json|--jsonl]
      instant-swift-data examples reminders tags [--json|--jsonl]
      instant-swift-data examples reminders list-tags [--json|--jsonl]
      instant-swift-data examples reminders search "text" [--list-id id] [--tag tag] [--include-completed] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(priorityList)] [--json|--jsonl]
      instant-swift-data examples reminders add-list "list title" [--json|--jsonl]
      instant-swift-data examples reminders rename-list <list-id> "new title" [--json|--jsonl]
      instant-swift-data examples reminders delete-list <list-id> [--json|--jsonl]
      instant-swift-data examples reminders add <list-id> "reminder title" [--notes text] [--due-date date] [--priority \(priorityList)] [--flagged] [--json|--jsonl]
      instant-swift-data examples reminders update <reminder-id> ["new title"] [--notes text] [--due-date date|--clear-due-date] [--priority \(priorityList)|none|--clear-priority] [--flagged|--unflagged] [--json|--jsonl]
      instant-swift-data examples reminders complete <reminder-id> [--json|--jsonl]
      instant-swift-data examples reminders delete <reminder-id> [--json|--jsonl]
      instant-swift-data examples reminders delete-completed [--list-id id] [--json|--jsonl]
      instant-swift-data examples reminders add-tag <reminder-id> <tag> [--json|--jsonl]
      instant-swift-data examples reminders remove-tag <reminder-id> <tag> [--json|--jsonl]
    """
  public static let seed =
    "Usage: instant-swift-data examples reminders seed [--json|--jsonl]"
  public static let list =
    "Usage: instant-swift-data examples reminders list [--refresh] [--list-id id] [--completed true|false] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(priorityList)] [--json|--jsonl]"
  public static let stats =
    "Usage: instant-swift-data examples reminders stats [--json|--jsonl]"
  public static let tags =
    "Usage: instant-swift-data examples reminders tags [--json|--jsonl]"
  public static let search =
    #"Usage: instant-swift-data examples reminders search "text" [--list-id id] [--tag tag] [--include-completed] [--flagged|--unflagged] [--scheduled] [--today] [--priority \#(priorityList)] [--json|--jsonl]"#
  public static let addList =
    #"Usage: instant-swift-data examples reminders add-list "list title""#
  public static let renameList =
    #"Usage: instant-swift-data examples reminders rename-list <list-id> "new title""#
  public static let deleteList =
    "Usage: instant-swift-data examples reminders delete-list <list-id>"
  public static let add =
    "Usage: instant-swift-data examples reminders add <list-id> \"reminder title\" [--notes text] [--due-date YYYY-MM-DD|ISO-8601|milliseconds] [--priority \(priorityList)] [--flagged] [--json|--jsonl]"
  public static let update =
    "Usage: instant-swift-data examples reminders update <reminder-id> [\"new title\"] [--notes text] [--due-date YYYY-MM-DD|ISO-8601|milliseconds] [--clear-due-date] [--priority \(priorityList)|none] [--clear-priority] [--flagged|--unflagged] [--json|--jsonl]"
  public static let complete =
    "Usage: instant-swift-data examples reminders complete <reminder-id>"
  public static let delete =
    "Usage: instant-swift-data examples reminders delete <reminder-id>"
  public static let deleteCompleted =
    "Usage: instant-swift-data examples reminders delete-completed [--list-id id]"
  public static let addTag =
    "Usage: instant-swift-data examples reminders add-tag <reminder-id> <tag>"
  public static let removeTag =
    "Usage: instant-swift-data examples reminders remove-tag <reminder-id> <tag>"
}

public enum CLIExamplesRemindersArgumentError: Error, Equatable, Sendable {
  case invalidArguments(String)

  public var exitCode: Int32 { 64 }
}

public struct CLIScaffoldInvocation: Equatable, Sendable {
  public var example: String
  public var outputDirectory: String
  public var force: Bool

  public init(example: String, outputDirectory: String, force: Bool = false) {
    self.example = example
    self.outputDirectory = outputDirectory
    self.force = force
  }
}

public enum CLIInitUsage {
  public static let initScaffold = """
    Usage: instant-swift-data init --example todos --to <directory> [--force] [--json|--jsonl]
    """
}

public enum CLIInitArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLISchemaInvocation: Equatable, Sendable {
  case generate(CLIGenerateArtifactInvocation)
  case verify(CLIVerifyArtifactInvocation)
}

public enum CLIPermissionsInvocation: Equatable, Sendable {
  case generate(CLIGenerateArtifactInvocation)
  case verify(CLIVerifyArtifactInvocation)
}

public struct CLIGenerateArtifactInvocation: Equatable, Sendable {
  public var example: String
  public var outputPath: String?

  public init(example: String, outputPath: String? = nil) {
    self.example = example
    self.outputPath = outputPath
  }
}

public struct CLIVerifyArtifactInvocation: Equatable, Sendable {
  public var example: String
  public var inputPath: String

  public init(example: String, inputPath: String) {
    self.example = example
    self.inputPath = inputPath
  }
}

public enum CLISchemaUsage {
  public static let generate =
    "Usage: instant-swift-data schema generate --example todos|validation|recording-action|sharing|voice-trail|mobile-chat|typing-indicator|reactions|avatar-stack|cursors|custom-cursors|merge-tile-game|stroopwafel|reminders|syncups|app-builder [--to instant.schema.ts] [--json|--jsonl]"
  public static let verify =
    "Usage: instant-swift-data schema verify --example todos|validation|recording-action|sharing|voice-trail|mobile-chat|typing-indicator|reactions|avatar-stack|cursors|custom-cursors|merge-tile-game|stroopwafel|reminders|syncups|app-builder --from instant.schema.ts"
}

public enum CLIPermissionsUsage {
  public static let generate =
    "Usage: instant-swift-data perms generate --example todos|validation|recording-action|sharing|voice-trail|mobile-chat|typing-indicator|reactions|avatar-stack|cursors|custom-cursors|merge-tile-game|stroopwafel|reminders|syncups|app-builder [--to instant.perms.ts] [--json|--jsonl]"
  public static let verify =
    "Usage: instant-swift-data perms verify --example todos|validation|recording-action|sharing|voice-trail|mobile-chat|typing-indicator|reactions|avatar-stack|cursors|custom-cursors|merge-tile-game|stroopwafel|reminders|syncups|app-builder --from instant.perms.ts"
}

public enum CLISchemaArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownGenerateOption(String, usage: String)
  case unknownVerifyOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIPermissionsArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownGenerateOption(String, usage: String)
  case unknownVerifyOption(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIQueryInvocation: Equatable, Sendable {
  case todos(CLITodosQueryInvocation)
}

public struct CLITodosQueryInvocation: Equatable, Sendable {
  public var completed: Bool?
  public var search: String?
  public var offset: Int?
  public var limit: Int?
  public var first: Int?
  public var after: CLIQueryCursor?
  public var last: Int?
  public var before: CLIQueryCursor?
  public var direction: CLIQuerySortDirection
  public var orderField: CLITodosQueryOrderField
  public var selectedFields: [String]?
  public var rawSnapshots: Bool

  public init(
    completed: Bool? = nil,
    search: String? = nil,
    offset: Int? = nil,
    limit: Int? = nil,
    first: Int? = nil,
    after: CLIQueryCursor? = nil,
    last: Int? = nil,
    before: CLIQueryCursor? = nil,
    direction: CLIQuerySortDirection = .ascending,
    orderField: CLITodosQueryOrderField = .createdAt,
    selectedFields: [String]? = nil,
    rawSnapshots: Bool = false
  ) {
    self.completed = completed
    self.search = search
    self.offset = offset
    self.limit = limit
    self.first = first
    self.after = after
    self.last = last
    self.before = before
    self.direction = direction
    self.orderField = orderField
    self.selectedFields = selectedFields
    self.rawSnapshots = rawSnapshots
  }
}

public struct CLIQueryCursor: Equatable, Sendable {
  public var entityID: String
  public var inclusive: Bool

  public init(entityID: String, inclusive: Bool = false) {
    self.entityID = entityID
    self.inclusive = inclusive
  }
}

public enum CLIQuerySortDirection: Equatable, Sendable {
  case ascending
  case descending
}

public enum CLITodosQueryOrderField: Equatable, Sendable {
  case none
  case createdAt
  case serverCreatedAt
}

public enum CLIQueryUsage {
  public static let query = """
    Usage: instant-swift-data query <namespace>
      instant-swift-data query todos [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--raw] [--select field[,field]] [--json|--jsonl]
    """

  public static let todosCommand = "instant-swift-data query todos"
  public static let todos =
    "\(todosCommand) [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--raw] [--select field[,field]]"
}

public enum CLIQueryArgumentError: Error, Equatable, Sendable {
  case invalidArguments(usage: String)
  case unknownOption(String, usage: String)
  case conflictingPagination(usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIValidationInvocation: Equatable, Sendable {
  case localTodos
  case localIntegrations
  case reminders
  case serverTransactionLoopback
  case cloudKitDemo
  case liveSession
  case liveTransaction
  case liveObserve
  case platformAdapters
  case parityReport
  case coverage
  case syncUpsRecording
  case typedDrafts
}

public enum CLIValidationRunnerInvocation: Equatable, Sendable {
  case localTodos
  case localIntegrations
  case reminders
  case serverTransactionLoopback
  case cloudKitDemo
  case liveSession
  case liveTransaction
  case liveObserve
  case liveSharing
  case liveSharingWriter
  case liveVoiceTrailRecordingsList
  case liveVoiceTrailV3Capture
  case liveTodosV3Write
  case liveTodosV3Observe
  case liveMobileChatV3Write
  case liveMobileChatV3Observe
  case liveAuthInvalidation
  case liveAuthV3App
  case livePlaybackRoom
  case liveTypingIndicatorV3
  case liveStreamsV3
  case liveCloudKitDemoV3
  case liveReactionsV3
  case liveAvatarStackV3
  case liveCursorsV3
  case liveCustomCursorsV3
  case liveMergeTileGameV3
  case liveStroopwafelV3
  case liveRemindersV3
  case liveSyncUpsV3
  case liveAppBuilderV3
  case livePreferences
  case typedDrafts
  case platformAdapters
  case syncUpsRecording
  case parityReport
  case coverage

  public var caseID: String {
    switch self {
    case .localTodos:
      "validation.local.todos"
    case .localIntegrations:
      "validation.local.integrations"
    case .reminders:
      "validation.reminders"
    case .serverTransactionLoopback:
      "validation.server.transaction.loopback"
    case .cloudKitDemo:
      "validation.cloudkit.demo"
    case .liveSession:
      "validation.live.session"
    case .liveTransaction:
      "validation.live.transaction"
    case .liveObserve:
      "validation.live.observe"
    case .liveSharing, .liveSharingWriter:
      "validation.live.sharing"
    case .liveVoiceTrailRecordingsList:
      "validation.live.voice-trail-recordings-list"
    case .liveVoiceTrailV3Capture:
      "validation.live.voice-trail-v3-capture"
    case .liveTodosV3Write:
      "validation.live.todos-v3-write"
    case .liveTodosV3Observe:
      "validation.live.todos-v3-observe"
    case .liveMobileChatV3Write:
      "validation.live.mobile-chat-v3-write"
    case .liveMobileChatV3Observe:
      "validation.live.mobile-chat-v3-observe"
    case .liveAuthInvalidation:
      "validation.live.auth-invalidation"
    case .liveAuthV3App:
      "validation.live.auth-v3-app"
    case .livePlaybackRoom:
      "validation.live.playback-room"
    case .liveTypingIndicatorV3:
      "validation.live.typing-indicator-v3"
    case .liveStreamsV3:
      "validation.live.streams-v3"
    case .liveCloudKitDemoV3:
      "validation.live.cloudkit-demo-v3"
    case .liveReactionsV3:
      "validation.live.reactions-v3"
    case .liveAvatarStackV3:
      "validation.live.avatar-stack-v3"
    case .liveCursorsV3:
      "validation.live.cursors-v3"
    case .liveCustomCursorsV3:
      "validation.live.custom-cursors-v3"
    case .liveMergeTileGameV3:
      "validation.live.merge-tile-game-v3"
    case .liveStroopwafelV3:
      "validation.live.stroopwafel-v3"
    case .liveRemindersV3:
      "validation.live.reminders-v3"
    case .liveSyncUpsV3:
      "validation.live.syncups-v3"
    case .liveAppBuilderV3:
      "validation.live.app-builder-v3"
    case .livePreferences:
      "validation.live.preferences"
    case .typedDrafts:
      "validation.typed.drafts"
    case .platformAdapters:
      "validation.platform.adapters"
    case .syncUpsRecording:
      "validation.syncups.recording"
    case .parityReport:
      "validation.parity.report"
    case .coverage:
      "validation.coverage"
    }
  }

  public var appID: String {
    switch self {
    case .serverTransactionLoopback:
      "server-transaction-loopback-validation"
    case .cloudKitDemo:
      "cloudkit-demo-validation"
    case .liveSession:
      "live-session-validation"
    case .liveTransaction:
      "live-transaction-validation"
    case .liveObserve:
      "live-observe-validation"
    case .liveSharing, .liveSharingWriter:
      "live-sharing-validation"
    case .liveVoiceTrailRecordingsList:
      "live-voice-trail-recordings-list"
    case .liveVoiceTrailV3Capture:
      "live-voice-trail-v3-capture"
    case .liveTodosV3Write, .liveTodosV3Observe:
      "live-todos-v3"
    case .liveMobileChatV3Write, .liveMobileChatV3Observe:
      "live-mobile-chat-v3"
    case .liveAuthInvalidation:
      "live-auth-invalidation"
    case .liveAuthV3App:
      "live-auth-v3-app"
    case .livePlaybackRoom:
      "live-playback-room"
    case .liveTypingIndicatorV3:
      "live-typing-indicator-v3"
    case .liveStreamsV3:
      "live-streams-v3"
    case .liveCloudKitDemoV3:
      "live-cloudkit-demo-v3"
    case .liveReactionsV3:
      "live-reactions-v3"
    case .liveAvatarStackV3:
      "live-avatar-stack-v3"
    case .liveCursorsV3:
      "live-cursors-v3"
    case .liveCustomCursorsV3:
      "live-custom-cursors-v3"
    case .liveMergeTileGameV3:
      "live-merge-tile-game-v3"
    case .liveStroopwafelV3:
      "live-stroopwafel-v3"
    case .liveRemindersV3:
      "live-reminders-v3"
    case .liveSyncUpsV3:
      "live-syncups-v3"
    case .liveAppBuilderV3:
      "live-app-builder-v3"
    case .livePreferences:
      "live-preferences"
    case .typedDrafts:
      "draft-validation"
    case .platformAdapters:
      "platform-adapter-validation"
    case .syncUpsRecording:
      "syncups-recording-validation"
    case .localTodos, .localIntegrations, .reminders, .parityReport, .coverage:
      "local-validation"
    }
  }
}

public enum CLIValidationUsage {
  public static let validation = """
    Usage: instant-swift-data validation <local-todos|local-integrations|reminders|server-transaction-loopback|cloudkit-demo|live-session|live-transaction|live-observe|typed-drafts|platform-adapters|syncups-recording|parity-report|coverage>
      instant-swift-data validation local-todos [--json|--jsonl]
      instant-swift-data validation local-integrations [--json|--jsonl]
      instant-swift-data validation reminders [--json|--jsonl]
      instant-swift-data validation server-transaction-loopback [--json|--jsonl]
      instant-swift-data validation cloudkit-demo [--json|--jsonl]
      instant-swift-data validation live-session [--json|--jsonl]
      instant-swift-data validation live-transaction [--json|--jsonl]
      instant-swift-data validation live-observe [--json|--jsonl]
      instant-swift-data validation typed-drafts [--json|--jsonl]
      instant-swift-data validation platform-adapters [--json|--jsonl]
      instant-swift-data validation syncups-recording [--json|--jsonl]
      instant-swift-data validation parity-report [--json|--jsonl]
      instant-swift-data validation coverage [--json|--jsonl]
    """
}

public enum CLIValidationRunnerUsage {
  public static let validationRunner =
    "Usage: instant-swift-data-validation-runner [--local-todos|--local-integrations|--reminders|--local-reminders|--server-transaction-loopback|--cloudkit-demo|--live-session|--live-transaction|--live-observe|--live-sharing|--live-sharing-writer|--live-voice-trail-recordings-list|--live-auth-invalidation|--live-auth-v3-app|--live-playback-room|--live-typing-indicator-v3|--live-streams-v3|--live-cloudkit-demo-v3|--live-reactions-v3|--live-avatar-stack-v3|--live-cursors-v3|--live-custom-cursors-v3|--live-merge-tile-game-v3|--live-stroopwafel-v3|--live-reminders-v3|--live-syncups-v3|--live-app-builder-v3|--live-preferences|--live-voice-trail-v3-capture|--live-todos-v3-write|--live-todos-v3-observe|--live-mobile-chat-v3-write|--live-mobile-chat-v3-observe|--typed-drafts|--platform-adapters|--syncups-recording|--parity-report|--coverage]"
}

public enum CLIValidationArgumentError: Error, Equatable, Sendable {
  case invalidArguments

  public var exitCode: Int32 { 64 }
}

public enum CLIValidationRunnerArgumentError: Error, Equatable, Sendable {
  case invalidArguments

  public var exitCode: Int32 { 64 }
}

public enum CLIAdminInvocation: Equatable, Sendable {
  case query(CLIAdminQueryInvocation)
  case transact(CLIAdminTransactInvocation)
}

public struct CLIAdminQueryInvocation: Equatable, Sendable {
  public var namespace: String
  public var limit: Int?

  public init(namespace: String, limit: Int? = nil) {
    self.namespace = namespace
    self.limit = limit
  }
}

public struct CLIAdminTransactInvocation: Equatable, Sendable {
  public var namespace: String
  public var entityID: String
  public var mergeJSON: String
  public var transactionID: String?

  public init(
    namespace: String,
    entityID: String,
    mergeJSON: String,
    transactionID: String? = nil
  ) {
    self.namespace = namespace
    self.entityID = entityID
    self.mergeJSON = mergeJSON
    self.transactionID = transactionID
  }
}

public enum CLIAdminUsage {
  public static let admin = """
    Usage: instant-swift-data admin <query|transact>
      instant-swift-data admin query <namespace> [--limit n] [--json|--jsonl]
      instant-swift-data admin transact <namespace> <entity-id> --merge '{...}' [--transaction-id id] [--json|--jsonl]
    """

  public static let query = "Usage: instant-swift-data admin query <namespace> [--limit n]"
  public static let transact =
    "Usage: instant-swift-data admin transact <namespace> <entity-id> --merge '{...}' [--transaction-id id]"
}

public enum CLIAdminArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case invalidNamespace(usage: String)
  case invalidEntityID(usage: String)
  case invalidLimit(usage: String)
  case invalidTransactionID(usage: String)
  case unknownOption(String, usage: String)

  public var exitCode: Int32 { 64 }
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

public enum CLISyncInvocation: Equatable, Sendable {
  case inspect
  case markProcessed(transactionID: String)
}

public enum CLISyncUsage {
  public static let sync = """
    Usage: instant-swift-data sync <inspect|mark-processed>
      instant-swift-data sync inspect [--json|--jsonl]
      instant-swift-data sync mark-processed <tx-id> [--json|--jsonl]
    """

  public static let inspect = "Usage: instant-swift-data sync inspect [--json|--jsonl]"
  public static let markProcessed =
    "Usage: instant-swift-data sync mark-processed <tx-id> [--json|--jsonl]"
}

public enum CLISyncArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIAppInvocation: Equatable, Sendable {
  case show
  case select(appID: String)
  case ephemeral(CLIAppEphemeralInvocation)
}

public struct CLIAppEphemeralInvocation: Equatable, Sendable {
  public var title: String

  public init(title: String) {
    self.title = title
  }
}

public enum CLIAppUsage {
  public static let app = """
    Usage: instant-swift-data app <show|select|ephemeral>
      instant-swift-data app show [--json|--jsonl]
      instant-swift-data app select <app-id> [--json|--jsonl]
      instant-swift-data app ephemeral --title <title> [--json|--jsonl]
    """

  public static let show = "Usage: instant-swift-data app show [--json|--jsonl]"
  public static let select = "Usage: instant-swift-data app select <app-id> [--json|--jsonl]"
  public static let ephemeral =
    "Usage: instant-swift-data app ephemeral --title <title> [--json|--jsonl]"
}

public enum CLIAppArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case unknownEphemeralOption(String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLICacheInvocation: Equatable, Sendable {
  case inspect
  case attributes(namespace: String?)
  case triples(namespace: String?)
}

public enum CLICacheUsage {
  public static let cache = """
    Usage: instant-swift-data cache <inspect|attributes|triples>
      instant-swift-data cache inspect [--json|--jsonl]
      instant-swift-data cache attributes [namespace] [--json|--jsonl]
      instant-swift-data cache triples [namespace] [--json|--jsonl]
    """

  public static let inspect = "Usage: instant-swift-data cache inspect [--json|--jsonl]"
  public static let attributes =
    "Usage: instant-swift-data cache attributes [namespace] [--json|--jsonl]"
  public static let triples =
    "Usage: instant-swift-data cache triples [namespace] [--json|--jsonl]"
}

public enum CLICacheArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case invalidNamespace(String, usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIOutboxInvocation: Equatable, Sendable {
  case inspect
  case transport(includeFailed: Bool)
  case flush(limit: Int?)
  case confirm(mutationID: String)
  case fail(mutationID: String, message: String)
  case retry(mutationID: String)
  case drain(limit: Int?)
}

public enum CLIOutboxUsage {
  public static let outbox = """
    Usage: instant-swift-data outbox <inspect|transport|flush|confirm|fail|retry|drain>
      instant-swift-data outbox inspect [--json|--jsonl]
      instant-swift-data outbox transport [--all] [--json|--jsonl]
      instant-swift-data outbox flush [--limit n] [--json|--jsonl]
      instant-swift-data outbox confirm <mutation-id> [--json|--jsonl]
      instant-swift-data outbox fail <mutation-id> "reason" [--json|--jsonl]
      instant-swift-data outbox retry <mutation-id> [--json|--jsonl]
      instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]
    """

  public static let inspect = "Usage: instant-swift-data outbox inspect [--json|--jsonl]"
  public static let transport =
    "Usage: instant-swift-data outbox transport [--all] [--json|--jsonl]"
  public static let flush =
    "Usage: instant-swift-data outbox flush [--limit n] [--json|--jsonl]"
  public static let confirm =
    "Usage: instant-swift-data outbox confirm <mutation-id> [--json|--jsonl]"
  public static let fail =
    "Usage: instant-swift-data outbox fail <mutation-id> \"reason\" [--json|--jsonl]"
  public static let retry =
    "Usage: instant-swift-data outbox retry <mutation-id> [--json|--jsonl]"
  public static let drain =
    "Usage: instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]"
}

public enum CLIOutboxArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case invalidArguments(usage: String)
  case unknownOption(String, usage: String)
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
  case create(CLIStreamCreateInvocation)
  case appendContent(CLIStreamAppendContentInvocation)
  case close(CLIStreamCloseInvocation)
  case readContent(CLIStreamContentReadInvocation)
  case watchContent(CLIStreamContentWatchInvocation)
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

public struct CLIStreamCreateInvocation: Equatable, Sendable {
  public var clientID: String

  public init(clientID: String) {
    self.clientID = clientID
  }
}

public struct CLIStreamAppendContentInvocation: Equatable, Sendable {
  public var streamID: String
  public var content: String
  public var expectedOffset: Int64?

  public init(streamID: String, content: String, expectedOffset: Int64? = nil) {
    self.streamID = streamID
    self.content = content
    self.expectedOffset = expectedOffset
  }
}

public struct CLIStreamCloseInvocation: Equatable, Sendable {
  public var streamID: String
  public var abortReason: String?

  public init(streamID: String, abortReason: String? = nil) {
    self.streamID = streamID
    self.abortReason = abortReason
  }
}

public enum CLIStreamContentSelector: Equatable, Sendable {
  case streamID(String)
  case clientID(String)
}

public struct CLIStreamContentReadInvocation: Equatable, Sendable {
  public var selector: CLIStreamContentSelector
  public var byteOffset: Int64

  public init(selector: CLIStreamContentSelector, byteOffset: Int64 = 0) {
    self.selector = selector
    self.byteOffset = byteOffset
  }
}

public struct CLIStreamContentWatchInvocation: Equatable, Sendable {
  public var selector: CLIStreamContentSelector
  public var byteOffset: Int64
  public var eventCount: Int

  public init(
    selector: CLIStreamContentSelector,
    byteOffset: Int64 = 0,
    eventCount: Int = 1
  ) {
    self.selector = selector
    self.byteOffset = byteOffset
    self.eventCount = eventCount
  }
}

public struct CLIStreamReadInvocation: Equatable, Sendable {
  public var streamID: String
  public var limit: Int?
  public var afterIndex: Int64?

  public init(streamID: String, limit: Int? = nil, afterIndex: Int64? = nil) {
    self.streamID = streamID
    self.limit = limit
    self.afterIndex = afterIndex
  }
}

public struct CLIStreamWatchOptionsInvocation: Equatable, Sendable {
  public var eventCount: Int
  public var afterIndex: Int64?

  public init(eventCount: Int = 1, afterIndex: Int64? = nil) {
    self.eventCount = eventCount
    self.afterIndex = afterIndex
  }
}

public struct CLIStreamWatchInvocation: Equatable, Sendable {
  public var streamID: String
  public var eventCount: Int
  public var afterIndex: Int64?

  public init(streamID: String, eventCount: Int = 1, afterIndex: Int64? = nil) {
    self.streamID = streamID
    self.eventCount = eventCount
    self.afterIndex = afterIndex
  }
}

public enum CLIStreamsUsage {
  public static let streams = """
    Usage: instant-swift-data streams <append|read|watch|create|append-content|close|read-content|watch-content>
      instant-swift-data streams append <stream-id> --value '{...}' [--json|--jsonl]
      instant-swift-data streams read <stream-id> [--limit n] [--after-index n] [--json|--jsonl]
      instant-swift-data streams watch <stream-id> [--events 1] [--after-index n] [--json|--jsonl]
      instant-swift-data streams create <client-id> [--json|--jsonl]
      instant-swift-data streams append-content <stream-id> --content 'text' [--offset n] [--json|--jsonl]
      instant-swift-data streams close <stream-id> [--abort-reason text] [--json|--jsonl]
      instant-swift-data streams read-content <stream-id>|--client-id <id> [--byte-offset n] [--json|--jsonl]
      instant-swift-data streams watch-content <stream-id>|--client-id <id> [--byte-offset n] [--events 1] [--json|--jsonl]
    """

  public static let append =
    "Usage: instant-swift-data streams append <stream-id> --value '{...}' [--json|--jsonl]"
  public static let read =
    "Usage: instant-swift-data streams read <stream-id> [--limit n] [--after-index n] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data streams watch <stream-id> [--events 1] [--after-index n] [--json|--jsonl]"
  public static let create =
    "Usage: instant-swift-data streams create <client-id> [--json|--jsonl]"
  public static let appendContent =
    "Usage: instant-swift-data streams append-content <stream-id> --content 'text' [--offset n] [--json|--jsonl]"
  public static let close =
    "Usage: instant-swift-data streams close <stream-id> [--abort-reason text] [--json|--jsonl]"
  public static let readContent =
    "Usage: instant-swift-data streams read-content <stream-id>|--client-id <id> [--byte-offset n] [--json|--jsonl]"
  public static let watchContent =
    "Usage: instant-swift-data streams watch-content <stream-id>|--client-id <id> [--byte-offset n] [--events 1] [--json|--jsonl]"
}

public enum CLIStreamsArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case missingValue(option: String, usage: String)
  case missingRequiredOption(option: String, usage: String)
  case invalidLimit(String, usage: String)
  case invalidAfterIndex(String, usage: String)
  case invalidOffset(option: String, value: String, usage: String)
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

private struct CLILiteralTokenParser<Output>: Parser {
  var token: String
  var output: Output

  init(_ token: String, output: Output) {
    self.token = token
    self.output = output
  }

  func parse(_ input: inout ArraySlice<String>) throws -> Output {
    try Backtracking {
      First<ArraySlice<String>>()
        .compactMap { token in
          token == self.token ? self.output : nil
        }
    }
    .parse(&input)
  }
}

public struct CLIOutputFlagParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIOutputMode {
    guard !input.isEmpty else {
      throw CLIArgumentParseError.missingOutputFlag
    }

    do {
      return try OneOf(input: ArraySlice<String>.self, output: CLIOutputMode.self) {
        CLILiteralTokenParser("--jsonl", output: CLIOutputMode.jsonl)
        CLILiteralTokenParser("--json", output: CLIOutputMode.json)
      }
      .parse(&input)
    } catch {
      throw CLIArgumentParseError.missingOutputFlag
    }
  }
}

public struct CLITopLevelCommandParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLITopLevelCommand {
    guard !input.isEmpty else {
      throw CLIArgumentParseError.missingCommand
    }

    return try OneOf(input: ArraySlice<String>.self, output: CLITopLevelCommand.self) {
      CLILiteralTokenParser("admin", output: CLITopLevelCommand.admin)
      CLILiteralTokenParser("app", output: CLITopLevelCommand.app)
      CLILiteralTokenParser("auth", output: CLITopLevelCommand.auth)
      CLILiteralTokenParser("benchmark", output: CLITopLevelCommand.benchmark)
      CLILiteralTokenParser("benchmarks", output: CLITopLevelCommand.benchmark)
      CLILiteralTokenParser("cache", output: CLITopLevelCommand.cache)
      CLILiteralTokenParser("connection", output: CLITopLevelCommand.connection)
      CLILiteralTokenParser("connect", output: CLITopLevelCommand.connection)
      CLILiteralTokenParser("examples", output: CLITopLevelCommand.examples)
      CLILiteralTokenParser("files", output: CLITopLevelCommand.files)
      CLILiteralTokenParser("storage", output: CLITopLevelCommand.files)
      CLILiteralTokenParser("help", output: CLITopLevelCommand.help)
      CLILiteralTokenParser("--help", output: CLITopLevelCommand.help)
      CLILiteralTokenParser("-h", output: CLITopLevelCommand.help)
      CLILiteralTokenParser("init", output: CLITopLevelCommand.initScaffold)
      CLILiteralTokenParser("local-id", output: CLITopLevelCommand.localID)
      CLILiteralTokenParser("localid", output: CLITopLevelCommand.localID)
      CLILiteralTokenParser("outbox", output: CLITopLevelCommand.outbox)
      CLILiteralTokenParser("perms", output: CLITopLevelCommand.permissions)
      CLILiteralTokenParser("permissions", output: CLITopLevelCommand.permissions)
      CLILiteralTokenParser("query", output: CLITopLevelCommand.query)
      CLILiteralTokenParser("rooms", output: CLITopLevelCommand.rooms)
      CLILiteralTokenParser("room", output: CLITopLevelCommand.rooms)
      CLILiteralTokenParser("schema", output: CLITopLevelCommand.schema)
      CLILiteralTokenParser("shares", output: CLITopLevelCommand.shares)
      CLILiteralTokenParser("share", output: CLITopLevelCommand.shares)
      CLILiteralTokenParser("sharing", output: CLITopLevelCommand.shares)
      CLILiteralTokenParser("streams", output: CLITopLevelCommand.streams)
      CLILiteralTokenParser("stream", output: CLITopLevelCommand.streams)
      CLILiteralTokenParser("sync", output: CLITopLevelCommand.sync)
      CLILiteralTokenParser("validate", output: CLITopLevelCommand.validation)
      CLILiteralTokenParser("validation", output: CLITopLevelCommand.validation)
      First<ArraySlice<String>>().map(CLITopLevelCommand.unknown)
    }
    .parse(&input)
  }
}

public struct CLIInvocationParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIInvocation {
    var arguments = Array(input)
    let output = CLIArguments.normalizeOutputMode(in: &arguments)
    var commandInput = arguments[...]
    let command =
      commandInput.isEmpty
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

    case "auth", "authentication", "magic-code-auth":
      return .auth(try CLIExamplesAuthLeafParser().parse(&input))

    case "app-builder", "appbuilder", "builder":
      return .appBuilder(try CLIExamplesAppBuilderLeafParser().parse(&input))

    case "chat":
      return .chat(try CLIExamplesChatLeafParser().parse(&input))

    case "counters", "cloudkit-demo":
      return .counters(try CLIExamplesCountersLeafParser().parse(&input))

    case "microblog":
      return .microblog(try CLIExamplesMicroblogLeafParser().parse(&input))

    case "mobile-chat", "mobilechat":
      return .mobileChat(try CLIExamplesMobileChatLeafParser().parse(&input))

    case "reactions", "reaction", "topics-reactions":
      return .reactions(try CLIExamplesReactionsLeafParser().parse(&input))

    case "typing-indicator", "typing", "typing-indicators":
      return .typingIndicator(try CLIExamplesTypingIndicatorLeafParser().parse(&input))

    case "avatar-stack", "avatars", "avatar-stack-recipe":
      return .avatarStack(try CLIExamplesAvatarStackLeafParser().parse(&input))

    case "cursors", "cursor":
      return .cursors(try CLIExamplesCursorsLeafParser().parse(&input))

    case "custom-cursors", "custom-cursor":
      return .customCursors(try CLIExamplesCustomCursorsLeafParser().parse(&input))

    case "merge-tile-game", "tile-game", "merge-game":
      return .mergeTileGame(try CLIExamplesMergeTileGameLeafParser().parse(&input))

    case "stroopwafel":
      return .stroopwafel(try CLIExamplesStroopwafelLeafParser().parse(&input))

    case "sync-ups", "syncups":
      return .syncUps(try CLIExamplesSyncUpsLeafParser().parse(&input))

    case "reminders":
      return .reminders(try CLIExamplesRemindersLeafParser().parse(&input))

    case "todo-links":
      return .todoLinks(try CLIExamplesTodoLinksLeafParser().parse(&input))

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
    guard let rawCommand = input.first else {
      return CLIExamplesTodosInvocation(command: nil, arguments: [])
    }

    let rawArguments = Array(input.dropFirst())
    let command = CLIExamplesTodosCommand(rawCommand)
    let leaf = try CLIExamplesTodosLeafParser().parse(&input)
    return CLIExamplesTodosInvocation(command: command, arguments: rawArguments, leaf: leaf)
  }
}

public struct CLIExamplesTodosCommandParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodosCommand {
    guard !input.isEmpty else {
      throw CLIArgumentParseError.missingCommand
    }

    return try OneOf(input: ArraySlice<String>.self, output: CLIExamplesTodosCommand.self) {
      CLILiteralTokenParser("seed", output: CLIExamplesTodosCommand.seed)
      CLILiteralTokenParser("add", output: CLIExamplesTodosCommand.add)
      CLILiteralTokenParser("list", output: CLIExamplesTodosCommand.list)
      CLILiteralTokenParser("watch", output: CLIExamplesTodosCommand.watch)
      CLILiteralTokenParser("observe", output: CLIExamplesTodosCommand.watch)
      CLILiteralTokenParser("complete", output: CLIExamplesTodosCommand.complete)
      CLILiteralTokenParser("update", output: CLIExamplesTodosCommand.update)
      CLILiteralTokenParser("edit", output: CLIExamplesTodosCommand.update)
      CLILiteralTokenParser("delete", output: CLIExamplesTodosCommand.delete)
      CLILiteralTokenParser("remove", output: CLIExamplesTodosCommand.delete)
      CLILiteralTokenParser("reset", output: CLIExamplesTodosCommand.reset)
      CLILiteralTokenParser("refresh", output: CLIExamplesTodosCommand.refresh)
      First<ArraySlice<String>>().map(CLIExamplesTodosCommand.unknown)
    }
    .parse(&input)
  }
}

public struct CLIExamplesTodosLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodosLeafInvocation {
    guard !input.isEmpty else {
      throw CLIExamplesTodosArgumentError.invalidArguments(usage: CLIExamplesTodosUsage.todos)
    }
    let command = try CLIExamplesTodosCommandParser().parse(&input)
    switch command {
    case .seed:
      try requireNoRemainingExamplesTodosArguments(&input, usage: CLIExamplesTodosUsage.seed)
      return .seed

    case .add:
      let text = joinedTrimmed(input)
      input.removeAll()
      guard !text.isEmpty else {
        throw CLIExamplesTodosArgumentError.invalidArguments(usage: CLIExamplesTodosUsage.add)
      }
      return .add(text: text)

    case .list:
      return .list(
        try CLIExamplesTodosQueryOptionsParser(
          usageCommand: CLIExamplesTodosUsage.listCommand,
          usage: CLIExamplesTodosUsage.list,
          unknown: { option, usage in
            CLIExamplesTodosArgumentError.unknownListOption(option, usage: usage)
          }
        )
        .parse(&input)
      )

    case .watch:
      return .watch(try CLIExamplesTodosWatchOptionsParser().parse(&input))

    case .complete:
      return .complete(
        todoID: try parseSingleExamplesTodosArgument(
          from: &input,
          usage: CLIExamplesTodosUsage.complete
        )
      )

    case .update:
      let todoID = try parseRequiredExamplesTodosArgument(
        from: &input,
        usage: CLIExamplesTodosUsage.update
      )
      let text = joinedTrimmed(input)
      input.removeAll()
      guard !text.isEmpty else {
        throw CLIExamplesTodosArgumentError.invalidArguments(usage: CLIExamplesTodosUsage.update)
      }
      return .update(todoID: todoID, text: text)

    case .delete:
      return .delete(
        todoID: try parseSingleExamplesTodosArgument(
          from: &input,
          usage: CLIExamplesTodosUsage.delete
        )
      )

    case .reset:
      try requireNoRemainingExamplesTodosArguments(&input, usage: CLIExamplesTodosUsage.reset)
      return .reset

    case .refresh:
      return .refresh(
        try CLIExamplesTodosQueryOptionsParser(
          usageCommand: CLIExamplesTodosUsage.listCommand,
          usage: CLIExamplesTodosUsage.list,
          unknown: { option, usage in
            CLIExamplesTodosArgumentError.unknownListOption(option, usage: usage)
          }
        )
        .parse(&input)
      )

    case let .unknown(command):
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesAuthLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesAuthLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesAuthArgumentError.invalidArguments(usage: CLIExamplesAuthUsage.auth)
    }
    input.removeFirst()

    switch command {
    case "send-code", "send", "magic-code-send":
      let email = try parseRawAuthRecipeArgument(from: &input, usage: CLIExamplesAuthUsage.sendCode)
      try requireNoRemainingExamplesAuthArguments(&input, usage: CLIExamplesAuthUsage.sendCode)
      return .sendCode(email: email)

    case "verify-code", "verify", "magic-code-verify":
      let email = try parseRawAuthRecipeArgument(
        from: &input, usage: CLIExamplesAuthUsage.verifyCode)
      let code = try parseRawAuthRecipeArgument(
        from: &input, usage: CLIExamplesAuthUsage.verifyCode)
      try requireNoRemainingExamplesAuthArguments(&input, usage: CLIExamplesAuthUsage.verifyCode)
      return .verifyCode(email: email, code: code)

    case "status", "show", "dashboard":
      try requireNoRemainingExamplesAuthArguments(&input, usage: CLIExamplesAuthUsage.status)
      return .status

    case "watch", "observe":
      return .watch(try CLIExamplesAuthWatchParser().parse(&input))

    case "sign-out", "signout", "logout":
      return .signOut(try CLIExamplesAuthSignOutParser().parse(&input))

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesAuthWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesAuthWatchInvocation {
    let usageCommand = "instant-swift-data examples auth watch"
    var eventCount = 1

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--events":
        let value = try parseAuthRecipeOptionValue(
          from: &input,
          option: option,
          usage: "Usage: \(usageCommand) --events 1"
        )
        guard let parsed = Int(value), parsed == 1 else {
          throw CLIExamplesAuthArgumentError.invalidEventCount(
            value,
            usageCommand: usageCommand
          )
        }
        eventCount = parsed

      default:
        throw CLIExamplesAuthArgumentError.unknownOption(
          domain: "examples auth watch",
          option: option,
          usage: CLIExamplesAuthUsage.watch
        )
      }
    }

    return CLIExamplesAuthWatchInvocation(eventCount: eventCount)
  }
}

public struct CLIExamplesAuthSignOutParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesAuthSignOutInvocation {
    var invalidateToken = true

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--invalidate-token":
        invalidateToken = true

      case "--skip-token-invalidation", "--no-invalidate-token":
        invalidateToken = false

      default:
        throw CLIExamplesAuthArgumentError.unknownOption(
          domain: "examples auth sign-out",
          option: option,
          usage: CLIExamplesAuthUsage.signOut
        )
      }
    }

    return CLIExamplesAuthSignOutInvocation(invalidateToken: invalidateToken)
  }
}

public struct CLIExamplesAppBuilderLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws
    -> CLIExamplesAppBuilderLeafInvocation
  {
    guard let command = input.first else {
      throw CLIExamplesAppBuilderArgumentError.invalidArguments(
        usage: CLIExamplesAppBuilderUsage.appBuilder
      )
    }
    input.removeFirst()

    switch command {
    case "generate", "create", "build":
      return .generate(try CLIExamplesAppBuilderGenerateParser().parse(&input))

    case "list", "builds":
      try requireNoRemainingExamplesAppBuilderArguments(
        &input,
        usage: CLIExamplesAppBuilderUsage.list
      )
      return .list

    case "show", "detail":
      let buildID = try parseRequiredAppBuilderArgument(
        from: &input,
        usage: CLIExamplesAppBuilderUsage.show
      )
      try requireNoRemainingExamplesAppBuilderArguments(
        &input,
        usage: CLIExamplesAppBuilderUsage.show
      )
      return .show(buildID: buildID)

    case "append", "update":
      return .append(try CLIExamplesAppBuilderAppendParser().parse(&input))

    case "finish", "previewable":
      let buildID = try parseRequiredAppBuilderArgument(
        from: &input,
        usage: CLIExamplesAppBuilderUsage.finish
      )
      try requireNoRemainingExamplesAppBuilderArguments(
        &input,
        usage: CLIExamplesAppBuilderUsage.finish
      )
      return .finish(buildID: buildID)

    case "reset":
      try requireNoRemainingExamplesAppBuilderArguments(
        &input,
        usage: CLIExamplesAppBuilderUsage.reset
      )
      return .reset

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesAppBuilderGenerateParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws
    -> CLIExamplesAppBuilderGenerateInvocation
  {
    var orgID = "local-instant-swift-data"
    var promptParts: [String] = []

    while let token = input.first {
      input.removeFirst()
      switch token {
      case "--org-id":
        orgID = try parseAppBuilderOptionValue(
          from: &input,
          option: token,
          usage: CLIExamplesAppBuilderUsage.generate
        )

      default:
        if token.hasPrefix("--") {
          throw CLIExamplesAppBuilderArgumentError.unknownOption(
            option: token,
            usage: CLIExamplesAppBuilderUsage.generate
          )
        }
        promptParts.append(token)
      }
    }

    let prompt = joinedTrimmed(promptParts[...])
    guard !prompt.isEmpty else {
      throw CLIExamplesAppBuilderArgumentError.invalidArguments(
        usage: CLIExamplesAppBuilderUsage.generate
      )
    }
    return CLIExamplesAppBuilderGenerateInvocation(prompt: prompt, orgID: orgID)
  }
}

public struct CLIExamplesAppBuilderAppendParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws
    -> CLIExamplesAppBuilderAppendInvocation
  {
    let buildID = try parseRequiredAppBuilderArgument(
      from: &input,
      usage: CLIExamplesAppBuilderUsage.append
    )
    var code: String?
    var reasoning: String?
    var isPreviewable: Bool?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--code":
        code = try parseAppBuilderOptionValue(
          from: &input,
          option: option,
          usage: CLIExamplesAppBuilderUsage.append
        )

      case "--reasoning":
        reasoning = try parseAppBuilderOptionValue(
          from: &input,
          option: option,
          usage: CLIExamplesAppBuilderUsage.append
        )

      case "--previewable":
        let value = try parseAppBuilderOptionValue(
          from: &input,
          option: option,
          usage: CLIExamplesAppBuilderUsage.append
        )
        guard let parsed = parseCLIQueryBool(value) else {
          throw CLIExamplesAppBuilderArgumentError.invalidArguments(
            usage: CLIExamplesAppBuilderUsage.append
          )
        }
        isPreviewable = parsed

      default:
        throw CLIExamplesAppBuilderArgumentError.unknownOption(
          option: option,
          usage: CLIExamplesAppBuilderUsage.append
        )
      }
    }

    guard code != nil || reasoning != nil || isPreviewable != nil else {
      throw CLIExamplesAppBuilderArgumentError.invalidArguments(
        usage: CLIExamplesAppBuilderUsage.append
      )
    }

    return CLIExamplesAppBuilderAppendInvocation(
      buildID: buildID,
      code: code,
      reasoning: reasoning,
      isPreviewable: isPreviewable
    )
  }
}

public struct CLIExamplesTodosQueryOptionsParser: Parser {
  private let usageCommand: String
  private let usage: String
  private let unknown: @Sendable (String, String) -> any Error

  public init(
    usageCommand: String,
    usage: String,
    unknown: @escaping @Sendable (String, String) -> any Error
  ) {
    self.usageCommand = usageCommand
    self.usage = usage
    self.unknown = unknown
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> CLITodosQueryInvocation {
    var invocation = CLITodosQueryInvocation()

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--completed":
        guard let value = input.first, let completed = parseCLIQueryBool(value) else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --completed true|false"
          )
        }
        input.removeFirst()
        invocation.completed = completed

      case "--search":
        guard let value = input.first,
          !trimmed(value).isEmpty
        else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --search text"
          )
        }
        input.removeFirst()
        invocation.search = value

      case "--offset":
        invocation.offset = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --offset n"
        )

      case "--limit":
        invocation.limit = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --limit n"
        )

      case "--first":
        invocation.first = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --first n"
        )

      case "--after", "--after-inclusive":
        invocation.after = try parseExamplesTodosCursor(
          from: &input,
          option: option,
          inclusive: option == "--after-inclusive",
          usageCommand: usageCommand
        )

      case "--last":
        invocation.last = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --last n"
        )

      case "--before", "--before-inclusive":
        invocation.before = try parseExamplesTodosCursor(
          from: &input,
          option: option,
          inclusive: option == "--before-inclusive",
          usageCommand: usageCommand
        )

      case "--order":
        guard let value = input.first, let direction = parseCLIQuerySortDirection(value) else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --order asc|desc"
          )
        }
        input.removeFirst()
        invocation.direction = direction

      case "--order-by":
        guard let value = input.first, let orderField = parseCLITodoOrderField(value) else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --order-by none|createdAt|serverCreatedAt"
          )
        }
        input.removeFirst()
        invocation.orderField = orderField

      default:
        throw unknown(option, usage)
      }
    }

    guard invocation.first == nil || invocation.last == nil else {
      throw CLIExamplesTodosArgumentError.invalidArguments(
        usage: "Use either --first or --last, not both. Usage: \(usage)"
      )
    }

    return invocation
  }
}

public struct CLIExamplesTodosWatchOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodosWatchInvocation {
    var invocation = CLIExamplesTodosWatchInvocation()
    let usageCommand = CLIExamplesTodosUsage.watchCommand
    let usage = CLIExamplesTodosUsage.watch

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--completed":
        guard let value = input.first, let completed = parseCLIQueryBool(value) else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --completed true|false"
          )
        }
        input.removeFirst()
        invocation.query.completed = completed

      case "--search":
        guard let value = input.first,
          !trimmed(value).isEmpty
        else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --search text"
          )
        }
        input.removeFirst()
        invocation.query.search = value

      case "--offset":
        invocation.query.offset = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --offset n"
        )

      case "--limit":
        invocation.query.limit = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --limit n"
        )

      case "--first":
        invocation.query.first = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --first n"
        )

      case "--after", "--after-inclusive":
        invocation.query.after = try parseExamplesTodosCursor(
          from: &input,
          option: option,
          inclusive: option == "--after-inclusive",
          usageCommand: usageCommand
        )

      case "--last":
        invocation.query.last = try parseExamplesTodosNonNegativeInt(
          from: &input,
          usage: "Usage: \(usageCommand) --last n"
        )

      case "--before", "--before-inclusive":
        invocation.query.before = try parseExamplesTodosCursor(
          from: &input,
          option: option,
          inclusive: option == "--before-inclusive",
          usageCommand: usageCommand
        )

      case "--order":
        guard let value = input.first, let direction = parseCLIQuerySortDirection(value) else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --order asc|desc"
          )
        }
        input.removeFirst()
        invocation.query.direction = direction

      case "--order-by":
        guard let value = input.first, let orderField = parseCLITodoOrderField(value) else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --order-by none|createdAt|serverCreatedAt"
          )
        }
        input.removeFirst()
        invocation.query.orderField = orderField

      case "--events":
        guard let value = input.first,
          let parsed = Int(value),
          parsed == 1
        else {
          throw CLIExamplesTodosArgumentError.invalidArguments(
            usage: "Usage: \(usageCommand) --events 1"
          )
        }
        input.removeFirst()
        invocation.eventCount = parsed

      default:
        throw CLIExamplesTodosArgumentError.unknownWatchOption(option, usage: usage)
      }
    }

    guard invocation.query.first == nil || invocation.query.last == nil else {
      throw CLIExamplesTodosArgumentError.invalidArguments(
        usage: "Use either --first or --last, not both. Usage: \(usage)"
      )
    }

    return invocation
  }
}

public struct CLIExamplesTodoLinksLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodoLinksLeafInvocation
  {
    guard let command = input.first else {
      throw CLIExamplesTodoLinksArgumentError.invalidArguments(
        usage: CLIExamplesTodoLinksUsage.todoLinks
      )
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesTodoLinksArguments(
        &input,
        usage: CLIExamplesTodoLinksUsage.seed
      )
      return .seed

    case "list":
      try requireNoRemainingExamplesTodoLinksArguments(
        &input,
        usage: CLIExamplesTodoLinksUsage.list
      )
      return .list

    case "nested":
      try requireNoRemainingExamplesTodoLinksArguments(
        &input,
        usage: CLIExamplesTodoLinksUsage.nested
      )
      return .nested

    case "unlink":
      try requireNoRemainingExamplesTodoLinksArguments(
        &input,
        usage: CLIExamplesTodoLinksUsage.unlink
      )
      return .unlink

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesCountersLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesCountersLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesCountersArgumentError.invalidArguments(
        usage: CLIExamplesCountersUsage.counters
      )
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesCountersArguments(
        &input,
        usage: CLIExamplesCountersUsage.seed
      )
      return .seed

    case "add":
      return .add(count: try parseExamplesCountersAddOptions(&input))

    case "list":
      try requireNoRemainingExamplesCountersArguments(
        &input,
        usage: CLIExamplesCountersUsage.list
      )
      return .list

    case "increment", "inc", "+":
      let counterID = try parseRequiredNonEmptyValue(
        from: &input,
        usage: CLIExamplesCountersUsage.increment
      )
      try requireNoRemainingExamplesCountersArguments(
        &input,
        usage: CLIExamplesCountersUsage.increment
      )
      return .increment(counterID: counterID)

    case "decrement", "dec", "-":
      let counterID = try parseRequiredNonEmptyValue(
        from: &input,
        usage: CLIExamplesCountersUsage.decrement
      )
      try requireNoRemainingExamplesCountersArguments(
        &input,
        usage: CLIExamplesCountersUsage.decrement
      )
      return .decrement(counterID: counterID)

    case "delete", "remove":
      let counterID = try parseRequiredNonEmptyValue(
        from: &input,
        usage: CLIExamplesCountersUsage.delete
      )
      try requireNoRemainingExamplesCountersArguments(
        &input,
        usage: CLIExamplesCountersUsage.delete
      )
      return .delete(counterID: counterID)

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

private func parseRequiredNonEmptyValue(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesCountersArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw CLIExamplesCountersArgumentError.invalidArguments(usage: usage)
  }
  return value
}

public struct CLIExamplesChatLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesChatLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesChatArgumentError.invalidArguments(
        usage: CLIExamplesChatUsage.chat
      )
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesChatArguments(
        &input,
        usage: CLIExamplesChatUsage.seed
      )
      return .seed

    case "channels":
      try requireNoRemainingExamplesChatArguments(
        &input,
        usage: CLIExamplesChatUsage.channels
      )
      return .channels

    case "messages":
      if input.isEmpty {
        return .messages(channelID: nil)
      }
      let channelID = try parseRequiredExamplesChatArgument(
        from: &input,
        usage: CLIExamplesChatUsage.messages
      )
      try requireNoRemainingExamplesChatArguments(
        &input,
        usage: CLIExamplesChatUsage.messages
      )
      return .messages(channelID: channelID)

    case "post", "send":
      return .post(try parseExamplesChatPostOptions(from: &input))

    case "reset":
      try requireNoRemainingExamplesChatArguments(
        &input,
        usage: CLIExamplesChatUsage.reset
      )
      return .reset

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesMicroblogLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesMicroblogLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesMicroblogArgumentError.invalidArguments(
        usage: CLIExamplesMicroblogUsage.microblog
      )
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesMicroblogArguments(
        &input,
        usage: CLIExamplesMicroblogUsage.seed
      )
      return .seed

    case "feed", "posts":
      try requireNoRemainingExamplesMicroblogArguments(
        &input,
        usage: CLIExamplesMicroblogUsage.feed
      )
      return .feed

    case "profiles":
      try requireNoRemainingExamplesMicroblogArguments(
        &input,
        usage: CLIExamplesMicroblogUsage.profiles
      )
      return .profiles

    case "profile":
      if input.isEmpty {
        return .profile(userID: nil)
      }
      let userID = try parseRequiredExamplesMicroblogArgument(
        from: &input,
        usage: CLIExamplesMicroblogUsage.profile
      )
      try requireNoRemainingExamplesMicroblogArguments(
        &input,
        usage: CLIExamplesMicroblogUsage.profile
      )
      return .profile(userID: userID)

    case "setup-profile", "create-profile":
      let displayName = try parseRequiredExamplesMicroblogArgument(
        from: &input,
        usage: CLIExamplesMicroblogUsage.setupProfile
      )
      let handle = try parseRequiredExamplesMicroblogArgument(
        from: &input,
        usage: CLIExamplesMicroblogUsage.setupProfile
      )
      try requireNoRemainingExamplesMicroblogArguments(
        &input,
        usage: CLIExamplesMicroblogUsage.setupProfile
      )
      return .setupProfile(displayName: displayName, handle: handle)

    case "post":
      return .post(try parseExamplesMicroblogPostOptions(from: &input))

    case "like":
      return .like(
        postID: try parseSingleExamplesMicroblogArgument(
          from: &input,
          usage: CLIExamplesMicroblogUsage.like
        )
      )

    case "unlike":
      return .unlike(
        postID: try parseSingleExamplesMicroblogArgument(
          from: &input,
          usage: CLIExamplesMicroblogUsage.unlike
        )
      )

    case "delete-post", "delete":
      return .deletePost(
        postID: try parseSingleExamplesMicroblogArgument(
          from: &input,
          usage: CLIExamplesMicroblogUsage.deletePost
        )
      )

    case "reset":
      try requireNoRemainingExamplesMicroblogArguments(
        &input,
        usage: CLIExamplesMicroblogUsage.reset
      )
      return .reset

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesMobileChatLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesMobileChatLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesMobileChatArgumentError.invalidArguments(
        usage: CLIExamplesMobileChatUsage.mobileChat
      )
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.seed
      )
      return .seed

    case "channels":
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.channels
      )
      return .channels

    case "messages":
      if input.isEmpty {
        return .messages(channelID: nil)
      }
      let channelID = try parseRequiredExamplesMobileChatArgument(
        from: &input,
        usage: CLIExamplesMobileChatUsage.messages
      )
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.messages
      )
      return .messages(channelID: channelID)

    case "profiles":
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.profiles
      )
      return .profiles

    case "profile":
      if input.isEmpty {
        return .profile(userID: nil)
      }
      let userID = try parseRequiredExamplesMobileChatArgument(
        from: &input,
        usage: CLIExamplesMobileChatUsage.profile
      )
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.profile
      )
      return .profile(userID: userID)

    case "setup-profile", "create-profile", "ensure-profile":
      let displayName = try parseRequiredExamplesMobileChatArgument(
        from: &input,
        usage: CLIExamplesMobileChatUsage.setupProfile
      )
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.setupProfile
      )
      return .setupProfile(displayName: displayName)

    case "send", "post":
      return .send(try parseExamplesMobileChatSendOptions(from: &input))

    case "join":
      return .join(
        channelID: try parseSingleExamplesMobileChatArgument(
          from: &input,
          usage: CLIExamplesMobileChatUsage.join
        )
      )

    case "presence":
      return .presence(
        channelID: try parseSingleExamplesMobileChatArgument(
          from: &input,
          usage: CLIExamplesMobileChatUsage.presence
        )
      )

    case "leave":
      return .leave(
        channelID: try parseSingleExamplesMobileChatArgument(
          from: &input,
          usage: CLIExamplesMobileChatUsage.leave
        )
      )

    case "reset":
      try requireNoRemainingExamplesMobileChatArguments(
        &input,
        usage: CLIExamplesMobileChatUsage.reset
      )
      return .reset

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesStroopwafelLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesStroopwafelLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesStroopwafelArgumentError.invalidArguments(
        usage: CLIExamplesStroopwafelUsage.stroopwafel
      )
    }
    input.removeFirst()

    switch command {
    case "setup-profile", "profile-set", "settings":
      return .setupProfile(
        handle: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.setupProfile
        )
      )

    case "profile":
      if input.isEmpty {
        return .profile(userID: nil)
      }
      let userID = try parseRequiredExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.profile
      )
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.profile
      )
      return .profile(userID: userID)

    case "score", "singleplayer-score":
      let rawScore = try parseSingleExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.score
      )
      guard let score = Int(rawScore), score >= 0 else {
        throw CLIExamplesStroopwafelArgumentError.invalidScore(
          rawScore,
          usage: CLIExamplesStroopwafelUsage.score
        )
      }
      return .score(score)

    case "create-room", "create-game":
      if input.isEmpty {
        return .createRoom(code: nil)
      }
      let code = try parseRequiredExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.createRoom
      )
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.createRoom
      )
      return .createRoom(code: code)

    case "rooms":
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.rooms
      )
      return .rooms

    case "room", "status":
      return .room(
        code: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.room
        )
      )

    case "join":
      return .join(
        code: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.join
        )
      )

    case "ready":
      return .ready(
        code: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.ready
        ),
        isReady: true
      )

    case "unready", "not-ready":
      return .ready(
        code: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.unready
        ),
        isReady: false
      )

    case "kick":
      let code = try parseRequiredExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.kick
      )
      let userID = try parseRequiredExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.kick
      )
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.kick
      )
      return .kick(code: code, userID: userID)

    case "start":
      return .start(
        code: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.start
        )
      )

    case "games":
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.games
      )
      return .games

    case "game":
      return .game(
        gameID: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.game
        )
      )

    case "tap":
      let gameID = try parseRequiredExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.tap
      )
      let color = try parseRequiredExamplesStroopwafelArgument(
        from: &input,
        usage: CLIExamplesStroopwafelUsage.tap
      )
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.tap
      )
      guard ["red", "green", "blue", "yellow"].contains(color.lowercased()) else {
        throw CLIExamplesStroopwafelArgumentError.invalidColor(
          color,
          usage: CLIExamplesStroopwafelUsage.tap
        )
      }
      return .tap(gameID: gameID, color: color.lowercased())

    case "leave":
      return .leave(
        code: try parseSingleExamplesStroopwafelArgument(
          from: &input,
          usage: CLIExamplesStroopwafelUsage.leave
        )
      )

    case "reset":
      try requireNoRemainingExamplesStroopwafelArguments(
        &input,
        usage: CLIExamplesStroopwafelUsage.reset
      )
      return .reset

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesReactionsLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesReactionsLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesReactionsArgumentError.invalidArguments(
        usage: CLIExamplesReactionsUsage.reactions
      )
    }
    input.removeFirst()

    switch command {
    case "tap", "send", "publish":
      return .tap(try parseExamplesReactionsTapOptions(from: &input))

    case "list", "messages":
      return .list(try parseExamplesReactionsListOptions(from: &input))

    case "watch", "observe":
      return .watch(try parseExamplesReactionsWatchOptions(from: &input))

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesTypingIndicatorLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesTypingIndicatorLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(
        usage: CLIExamplesTypingIndicatorUsage.typingIndicator
      )
    }
    input.removeFirst()

    switch command {
    case "join", "enter":
      return .join(
        userID: try parseSingleExamplesTypingIndicatorUserID(from: &input)
      )

    case "type", "typing", "start":
      return .type(
        userID: try parseSingleExamplesTypingIndicatorUserID(from: &input)
      )

    case "stop", "blur":
      return .stop(
        userID: try parseSingleExamplesTypingIndicatorUserID(from: &input)
      )

    case "list", "presence":
      return .list(try parseExamplesTypingIndicatorListOptions(from: &input))

    case "watch", "observe":
      return .watch(try parseExamplesTypingIndicatorWatchOptions(from: &input))

    case "leave":
      return .leave(
        userID: try parseSingleExamplesTypingIndicatorUserID(from: &input)
      )

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesAvatarStackLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesAvatarStackLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesAvatarStackArgumentError.invalidArguments(
        usage: CLIExamplesAvatarStackUsage.avatarStack
      )
    }
    input.removeFirst()

    switch command {
    case "join", "enter":
      return .join(try parseExamplesAvatarStackJoinOptions(from: &input))

    case "list", "presence":
      return .list(try parseExamplesAvatarStackListOptions(from: &input))

    case "watch", "observe":
      return .watch(try parseExamplesAvatarStackWatchOptions(from: &input))

    case "leave":
      return .leave(
        userID: try parseSingleExamplesAvatarStackUserID(
          from: &input,
          usage: CLIExamplesAvatarStackUsage.leave
        )
      )

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesCursorsLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesCursorsLeafInvocation {
    try parseExamplesCursorsLeaf(
      from: &input,
      rootUsage: CLIExamplesCursorsUsage.cursors,
      moveUsage: CLIExamplesCursorsUsage.move,
      listUsage: CLIExamplesCursorsUsage.list,
      watchUsage: CLIExamplesCursorsUsage.watch,
      userUsage: CLIExamplesCursorsUsage.user,
      allowsName: false
    )
  }
}

public struct CLIExamplesCustomCursorsLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesCursorsLeafInvocation {
    try parseExamplesCursorsLeaf(
      from: &input,
      rootUsage: CLIExamplesCustomCursorsUsage.customCursors,
      moveUsage: CLIExamplesCustomCursorsUsage.move,
      listUsage: CLIExamplesCustomCursorsUsage.list,
      watchUsage: CLIExamplesCustomCursorsUsage.watch,
      userUsage: CLIExamplesCustomCursorsUsage.user,
      allowsName: true
    )
  }
}

public struct CLIExamplesMergeTileGameLeafParser: Parser {
  public init() {}

  public func parse(
    _ input: inout ArraySlice<String>
  ) throws -> CLIExamplesMergeTileGameLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesMergeTileGameArgumentError.invalidArguments(
        usage: CLIExamplesMergeTileGameUsage.mergeTileGame
      )
    }
    input.removeFirst()

    switch command {
    case "join", "enter":
      return .join(try parseExamplesMergeTileGameJoinOptions(from: &input))

    case "tap", "paint", "color":
      return .tap(try parseExamplesMergeTileGameTapOptions(from: &input))

    case "board", "list", "state":
      return .board(try parseExamplesMergeTileGameBoardOptions(from: &input))

    case "watch", "observe":
      return .watch(try parseExamplesMergeTileGameWatchOptions(from: &input))

    case "reset":
      try requireNoRemainingExamplesMergeTileGameArguments(
        &input,
        usage: CLIExamplesMergeTileGameUsage.reset
      )
      return .reset

    case "leave":
      return .leave(
        userID: try parseSingleExamplesMergeTileGameUserID(
          from: &input,
          usage: CLIExamplesMergeTileGameUsage.leave
        )
      )

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesSyncUpsLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesSyncUpsLeafInvocation {
    guard let command = input.first else {
      throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.syncUps)
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesSyncUpsArguments(&input, usage: CLIExamplesSyncUpsUsage.seed)
      return .seed

    case "list", "refresh":
      return .list(try parseExamplesSyncUpsListOptions(from: &input, command: command))

    case "detail":
      return .detail(
        syncUpID: try parseSingleExamplesSyncUpsArgument(
          from: &input,
          usage: CLIExamplesSyncUpsUsage.detail
        )
      )

    case "add":
      return .add(try parseExamplesSyncUpsAddOptions(from: &input))

    case "update", "edit":
      return .update(try parseExamplesSyncUpsUpdateOptions(from: &input, command: command))

    case "add-attendee":
      let syncUpID = try parseRequiredExamplesSyncUpsArgument(
        from: &input,
        usage: CLIExamplesSyncUpsUsage.addAttendee
      )
      let name = joinedTrimmed(input)
      input.removeAll()
      guard !name.isEmpty else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments(
          CLIExamplesSyncUpsUsage.addAttendee
        )
      }
      return .addAttendee(syncUpID: syncUpID, name: name)

    case "record", "record-meeting":
      let record = try parseExamplesSyncUpsRecordOptions(from: &input)
      return .record(syncUpID: record.syncUpID, transcript: record.transcript)

    case "record-demo", "recording-demo":
      return .recordDemo(
        syncUpID: try parseSingleExamplesSyncUpsArgument(
          from: &input,
          usage: CLIExamplesSyncUpsUsage.recordDemo
        )
      )

    case "delete":
      return .delete(
        syncUpID: try parseSingleExamplesSyncUpsArgument(
          from: &input,
          usage: CLIExamplesSyncUpsUsage.delete
        )
      )

    case "delete-attendee":
      return .deleteAttendee(
        attendeeID: try parseSingleExamplesSyncUpsArgument(
          from: &input,
          usage: CLIExamplesSyncUpsUsage.deleteAttendee
        )
      )

    case "delete-meeting":
      return .deleteMeeting(
        meetingID: try parseSingleExamplesSyncUpsArgument(
          from: &input,
          usage: CLIExamplesSyncUpsUsage.deleteMeeting
        )
      )

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesRemindersLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesRemindersLeafInvocation
  {
    guard let command = input.first else {
      throw CLIExamplesRemindersArgumentError.invalidArguments(
        CLIExamplesRemindersUsage.reminders
      )
    }
    input.removeFirst()

    switch command {
    case "seed":
      try requireNoRemainingExamplesRemindersArguments(
        &input,
        usage: CLIExamplesRemindersUsage.seed
      )
      return .seed

    case "list", "lists", "refresh":
      return .list(try parseExamplesRemindersListOptions(from: &input, command: command))

    case "stats":
      try requireNoRemainingExamplesRemindersArguments(
        &input,
        usage: CLIExamplesRemindersUsage.stats
      )
      return .stats

    case "tags", "list-tags":
      try requireNoRemainingExamplesRemindersArguments(
        &input,
        usage: command == "list-tags"
          ? "Usage: instant-swift-data examples reminders list-tags [--json|--jsonl]"
          : CLIExamplesRemindersUsage.tags
      )
      return .tags

    case "add-list":
      let title = joinedTrimmed(input)
      input.removeAll()
      guard !title.isEmpty else {
        throw CLIExamplesRemindersArgumentError.invalidArguments(
          CLIExamplesRemindersUsage.addList
        )
      }
      return .addList(title: title)

    case "rename-list", "update-list":
      let listID = try parseRequiredExamplesRemindersArgument(
        from: &input,
        usage: CLIExamplesRemindersUsage.renameList
      )
      let title = joinedTrimmed(input)
      input.removeAll()
      guard !title.isEmpty else {
        throw CLIExamplesRemindersArgumentError.invalidArguments(
          CLIExamplesRemindersUsage.renameList
        )
      }
      return .renameList(listID: listID, title: title)

    case "add":
      return .add(try parseExamplesReminderAddOptions(from: &input))

    case "update", "edit":
      return .update(try parseExamplesReminderUpdateOptions(from: &input))

    case "complete":
      return .complete(
        reminderID: try parseSingleExamplesRemindersArgument(
          from: &input,
          usage: CLIExamplesRemindersUsage.complete
        )
      )

    case "delete":
      return .delete(
        reminderID: try parseSingleExamplesRemindersArgument(
          from: &input,
          usage: CLIExamplesRemindersUsage.delete
        )
      )

    case "delete-completed":
      return .deleteCompleted(
        listID: try parseExamplesRemindersDeleteCompletedOptions(from: &input)
      )

    case "delete-list":
      return .deleteList(
        listID: try parseSingleExamplesRemindersArgument(
          from: &input,
          usage: CLIExamplesRemindersUsage.deleteList
        )
      )

    case "add-tag", "tag":
      let (reminderID, rawTag) = try parseExamplesReminderTagArguments(
        from: &input,
        usage: CLIExamplesRemindersUsage.addTag
      )
      return .addTag(reminderID: reminderID, rawTag: rawTag)

    case "remove-tag", "untag":
      let (reminderID, rawTag) = try parseExamplesReminderTagArguments(
        from: &input,
        usage: CLIExamplesRemindersUsage.removeTag
      )
      return .removeTag(reminderID: reminderID, rawTag: rawTag)

    case "search":
      return .search(try parseExamplesRemindersSearchOptions(from: &input))

    default:
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIInitParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIScaffoldInvocation {
    try CLIInitOptionsParser().parse(&input)
  }
}

public struct CLIInitOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIScaffoldInvocation {
    var example: String?
    var outputDirectory: String?
    var force = false

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--example":
        guard let value = input.first else {
          throw CLIInitArgumentError.invalidArguments(usage: CLIInitUsage.initScaffold)
        }
        input.removeFirst()
        example = value

      case "--to":
        guard let value = input.first,
          !trimmed(value).isEmpty
        else {
          throw CLIInitArgumentError.invalidArguments(usage: CLIInitUsage.initScaffold)
        }
        input.removeFirst()
        outputDirectory = value

      case "--force":
        force = true

      default:
        throw CLIInitArgumentError.unknownOption(option, usage: CLIInitUsage.initScaffold)
      }
    }

    guard let example, let outputDirectory else {
      throw CLIInitArgumentError.invalidArguments(usage: CLIInitUsage.initScaffold)
    }
    return CLIScaffoldInvocation(example: example, outputDirectory: outputDirectory, force: force)
  }
}

public struct CLISchemaParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLISchemaInvocation {
    if input.first == "verify" {
      return .verify(
        try CLISchemaVerifyParser().parse(&input)
      )
    }
    return .generate(
      try CLISchemaGenerateParser().parse(&input)
    )
  }
}

public struct CLISchemaGenerateParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIGenerateArtifactInvocation {
    try requireSchemaCommand("generate", from: &input, usage: CLISchemaUsage.generate)
    let parser = CLIGenerateArtifactOptionsParser(
      usage: CLISchemaUsage.generate,
      unknown: { option, usage in
        CLISchemaArgumentError.unknownGenerateOption(option, usage: usage)
      },
      invalid: { usage in
        CLISchemaArgumentError.invalidArguments(usage: usage)
      }
    )
    return try parser.parse(&input)
  }
}

public struct CLISchemaVerifyParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIVerifyArtifactInvocation {
    try requireSchemaCommand("verify", from: &input, usage: CLISchemaUsage.verify)
    let parser = CLIVerifyArtifactOptionsParser(
      usage: CLISchemaUsage.verify,
      unknown: { option, usage in
        CLISchemaArgumentError.unknownVerifyOption(option, usage: usage)
      },
      invalid: { usage in
        CLISchemaArgumentError.invalidArguments(usage: usage)
      }
    )
    return try parser.parse(&input)
  }
}

public struct CLIPermissionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIPermissionsInvocation {
    if input.first == "verify" {
      return .verify(
        try CLIPermissionsVerifyParser().parse(&input)
      )
    }
    return .generate(
      try CLIPermissionsGenerateParser().parse(&input)
    )
  }
}

public struct CLIPermissionsGenerateParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIGenerateArtifactInvocation {
    try requirePermissionsCommand("generate", from: &input, usage: CLIPermissionsUsage.generate)
    let parser = CLIGenerateArtifactOptionsParser(
      usage: CLIPermissionsUsage.generate,
      unknown: { option, usage in
        CLIPermissionsArgumentError.unknownGenerateOption(option, usage: usage)
      },
      invalid: { usage in
        CLIPermissionsArgumentError.invalidArguments(usage: usage)
      }
    )
    return try parser.parse(&input)
  }
}

public struct CLIPermissionsVerifyParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIVerifyArtifactInvocation {
    try requirePermissionsCommand("verify", from: &input, usage: CLIPermissionsUsage.verify)
    let parser = CLIVerifyArtifactOptionsParser(
      usage: CLIPermissionsUsage.verify,
      unknown: { option, usage in
        CLIPermissionsArgumentError.unknownVerifyOption(option, usage: usage)
      },
      invalid: { usage in
        CLIPermissionsArgumentError.invalidArguments(usage: usage)
      }
    )
    return try parser.parse(&input)
  }
}

public struct CLIGenerateArtifactOptionsParser: Parser {
  private let usage: String
  private let unknown: @Sendable (String, String) -> any Error
  private let invalid: @Sendable (String) -> any Error

  public init(
    usage: String,
    unknown: @escaping @Sendable (String, String) -> any Error,
    invalid: @escaping @Sendable (String) -> any Error
  ) {
    self.usage = usage
    self.unknown = unknown
    self.invalid = invalid
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIGenerateArtifactInvocation {
    var example: String?
    var outputPath: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--example":
        guard let value = input.first else {
          throw invalid(usage)
        }
        input.removeFirst()
        example = value

      case "--to":
        guard let value = input.first else {
          throw invalid(usage)
        }
        input.removeFirst()
        outputPath = value

      default:
        throw unknown(option, usage)
      }
    }

    guard let example else {
      throw invalid(usage)
    }
    return CLIGenerateArtifactInvocation(example: example, outputPath: outputPath)
  }
}

public struct CLIVerifyArtifactOptionsParser: Parser {
  private let usage: String
  private let unknown: @Sendable (String, String) -> any Error
  private let invalid: @Sendable (String) -> any Error

  public init(
    usage: String,
    unknown: @escaping @Sendable (String, String) -> any Error,
    invalid: @escaping @Sendable (String) -> any Error
  ) {
    self.usage = usage
    self.unknown = unknown
    self.invalid = invalid
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIVerifyArtifactInvocation {
    var example: String?
    var inputPath: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--example":
        guard let value = input.first else {
          throw invalid(usage)
        }
        input.removeFirst()
        example = value

      case "--from":
        guard let value = input.first else {
          throw invalid(usage)
        }
        input.removeFirst()
        inputPath = value

      default:
        throw unknown(option, usage)
      }
    }

    guard let example, let inputPath else {
      throw invalid(usage)
    }
    return CLIVerifyArtifactInvocation(example: example, inputPath: inputPath)
  }
}

public struct CLIQueryParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIQueryInvocation {
    guard let namespace = input.first else {
      throw CLIQueryArgumentError.invalidArguments(usage: CLIQueryUsage.query)
    }
    input.removeFirst()

    switch namespace {
    case "todos":
      return .todos(try CLITodosQueryParser().parse(&input))

    default:
      throw CLIQueryArgumentError.invalidArguments(usage: CLIQueryUsage.query)
    }
  }
}

public struct CLITodosQueryParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLITodosQueryInvocation {
    var invocation = CLITodosQueryInvocation()

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--completed":
        guard let value = input.first, let completed = parseCLIQueryBool(value) else {
          throw CLIQueryArgumentError.invalidArguments(
            usage: "Usage: \(CLIQueryUsage.todosCommand) --completed true|false"
          )
        }
        input.removeFirst()
        invocation.completed = completed

      case "--search":
        guard let value = input.first,
          !trimmed(value).isEmpty
        else {
          throw CLIQueryArgumentError.invalidArguments(
            usage: "Usage: \(CLIQueryUsage.todosCommand) --search text"
          )
        }
        input.removeFirst()
        invocation.search = value

      case "--offset":
        invocation.offset = try parseCLIQueryNonNegativeInt(
          from: &input,
          usage: "Usage: \(CLIQueryUsage.todosCommand) --offset n"
        )

      case "--limit":
        invocation.limit = try parseCLIQueryNonNegativeInt(
          from: &input,
          usage: "Usage: \(CLIQueryUsage.todosCommand) --limit n"
        )

      case "--first":
        invocation.first = try parseCLIQueryNonNegativeInt(
          from: &input,
          usage: "Usage: \(CLIQueryUsage.todosCommand) --first n"
        )

      case "--after", "--after-inclusive":
        invocation.after = try parseCLIQueryCursor(
          from: &input,
          option: option,
          inclusive: option == "--after-inclusive"
        )

      case "--last":
        invocation.last = try parseCLIQueryNonNegativeInt(
          from: &input,
          usage: "Usage: \(CLIQueryUsage.todosCommand) --last n"
        )

      case "--before", "--before-inclusive":
        invocation.before = try parseCLIQueryCursor(
          from: &input,
          option: option,
          inclusive: option == "--before-inclusive"
        )

      case "--order":
        guard let value = input.first, let direction = parseCLIQuerySortDirection(value) else {
          throw CLIQueryArgumentError.invalidArguments(
            usage: "Usage: \(CLIQueryUsage.todosCommand) --order asc|desc"
          )
        }
        input.removeFirst()
        invocation.direction = direction

      case "--order-by":
        guard let value = input.first, let orderField = parseCLITodoOrderField(value) else {
          throw CLIQueryArgumentError.invalidArguments(
            usage: "Usage: \(CLIQueryUsage.todosCommand) --order-by none|createdAt|serverCreatedAt"
          )
        }
        input.removeFirst()
        invocation.orderField = orderField

      case "--raw", "--snapshots":
        invocation.rawSnapshots = true

      case "--select":
        guard let value = input.first else {
          throw CLIQueryArgumentError.invalidArguments(
            usage: "Usage: \(CLIQueryUsage.todosCommand) --select field[,field]"
          )
        }
        input.removeFirst()
        invocation.selectedFields = try parseCLITodoSelectedFields(value)
        invocation.rawSnapshots = true

      default:
        throw CLIQueryArgumentError.unknownOption(option, usage: CLIQueryUsage.todos)
      }
    }

    guard invocation.first == nil || invocation.last == nil else {
      throw CLIQueryArgumentError.conflictingPagination(usage: CLIQueryUsage.todos)
    }

    return invocation
  }
}

public struct CLIValidationParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIValidationInvocation {
    guard let command = input.first else {
      throw CLIValidationArgumentError.invalidArguments
    }
    input.removeFirst()
    guard input.isEmpty else {
      throw CLIValidationArgumentError.invalidArguments
    }

    switch command {
    case "local-todos", "todos":
      return .localTodos

    case "local-integrations", "integrations":
      return .localIntegrations

    case "reminders", "local-reminders":
      return .reminders

    case "server-transaction-loopback", "server-loopback", "transport-loopback", "inbound-loopback":
      return .serverTransactionLoopback

    case "cloudkit-demo", "cloudkit", "shared-counters":
      return .cloudKitDemo

    case "live-session", "websocket-session", "ws-session":
      return .liveSession

    case "live-transaction", "websocket-transaction", "ws-transaction":
      return .liveTransaction

    case "live-observe", "websocket-observe", "ws-observe":
      return .liveObserve

    case "parity-report", "parity":
      return .parityReport

    case "coverage":
      return .coverage

    case "typed-drafts", "drafts":
      return .typedDrafts

    case "platform-adapters", "adapters", "wrappers":
      return .platformAdapters

    case "syncups-recording", "sync-ups-recording", "recording", "syncups":
      return .syncUpsRecording

    default:
      throw CLIValidationArgumentError.invalidArguments
    }
  }
}

public struct CLIValidationRunnerParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIValidationRunnerInvocation {
    guard let flag = input.first else {
      return .localTodos
    }
    input.removeFirst()
    guard input.isEmpty else {
      throw CLIValidationRunnerArgumentError.invalidArguments
    }

    switch flag {
    case "--local-todos":
      return .localTodos

    case "--local-integrations":
      return .localIntegrations

    case "--reminders", "--local-reminders":
      return .reminders

    case "--server-transaction-loopback", "--server-loopback", "--transport-loopback":
      return .serverTransactionLoopback

    case "--cloudkit-demo", "--cloudkit", "--shared-counters":
      return .cloudKitDemo

    case "--live-session", "--websocket-session", "--ws-session":
      return .liveSession

    case "--live-transaction", "--websocket-transaction", "--ws-transaction":
      return .liveTransaction

    case "--live-observe", "--websocket-observe", "--ws-observe":
      return .liveObserve

    case "--live-sharing":
      return .liveSharing

    case "--live-sharing-writer":
      return .liveSharingWriter

    case "--live-voice-trail-recordings-list":
      return .liveVoiceTrailRecordingsList

    case "--live-voice-trail-v3-capture":
      return .liveVoiceTrailV3Capture

    case "--live-todos-v3-write":
      return .liveTodosV3Write

    case "--live-todos-v3-observe":
      return .liveTodosV3Observe

    case "--live-mobile-chat-v3-write":
      return .liveMobileChatV3Write

    case "--live-mobile-chat-v3-observe":
      return .liveMobileChatV3Observe

    case "--live-auth-invalidation":
      return .liveAuthInvalidation

    case "--live-auth-v3-app":
      return .liveAuthV3App

    case "--live-playback-room":
      return .livePlaybackRoom

    case "--live-typing-indicator-v3":
      return .liveTypingIndicatorV3

    case "--live-streams-v3":
      return .liveStreamsV3

    case "--live-cloudkit-demo-v3":
      return .liveCloudKitDemoV3

    case "--live-reactions-v3":
      return .liveReactionsV3

    case "--live-avatar-stack-v3":
      return .liveAvatarStackV3

    case "--live-cursors-v3":
      return .liveCursorsV3

    case "--live-custom-cursors-v3":
      return .liveCustomCursorsV3

    case "--live-merge-tile-game-v3":
      return .liveMergeTileGameV3

    case "--live-stroopwafel-v3":
      return .liveStroopwafelV3

    case "--live-reminders-v3":
      return .liveRemindersV3

    case "--live-syncups-v3":
      return .liveSyncUpsV3

    case "--live-app-builder-v3":
      return .liveAppBuilderV3

    case "--live-preferences":
      return .livePreferences

    case "--typed-drafts":
      return .typedDrafts

    case "--platform-adapters":
      return .platformAdapters

    case "--syncups-recording":
      return .syncUpsRecording

    case "--parity-report":
      return .parityReport

    case "--coverage":
      return .coverage

    default:
      throw CLIValidationRunnerArgumentError.invalidArguments
    }
  }
}

public struct CLIAdminParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAdminInvocation {
    guard let command = input.first else {
      throw CLIAdminArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "query":
      return .query(try CLIAdminQueryParser().parse(&input))

    case "transact", "tx":
      return .transact(try CLIAdminTransactParser().parse(&input))

    default:
      throw CLIAdminArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIAdminQueryParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAdminQueryInvocation {
    let namespace = try parseRequiredAdminNamespace(from: &input, usage: CLIAdminUsage.query)
    var limit: Int?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--limit":
        guard let value = input.first,
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIAdminArgumentError.invalidLimit(usage: CLIAdminUsage.query)
        }
        input.removeFirst()
        limit = parsed

      default:
        throw CLIAdminArgumentError.unknownOption(option, usage: CLIAdminUsage.query)
      }
    }

    return CLIAdminQueryInvocation(namespace: namespace, limit: limit)
  }
}

public struct CLIAdminTransactParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAdminTransactInvocation {
    let namespace = try parseRequiredAdminNamespace(from: &input, usage: CLIAdminUsage.transact)
    let entityID = try parseRequiredAdminEntityID(from: &input, usage: CLIAdminUsage.transact)
    var mergeJSON: String?
    var transactionID: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--merge":
        guard mergeJSON == nil, let value = input.first else {
          throw CLIAdminArgumentError.missingArguments(usage: CLIAdminUsage.transact)
        }
        input.removeFirst()
        mergeJSON = value

      case "--transaction-id":
        guard transactionID == nil, let value = input.first else {
          throw CLIAdminArgumentError.missingArguments(usage: CLIAdminUsage.transact)
        }
        input.removeFirst()
        let trimmedValue = trimmed(value)
        guard !trimmedValue.isEmpty else {
          throw CLIAdminArgumentError.invalidTransactionID(usage: CLIAdminUsage.transact)
        }
        transactionID = trimmedValue

      default:
        throw CLIAdminArgumentError.unknownOption(option, usage: CLIAdminUsage.transact)
      }
    }

    guard let mergeJSON else {
      throw CLIAdminArgumentError.missingArguments(usage: CLIAdminUsage.transact)
    }
    return CLIAdminTransactInvocation(
      namespace: namespace,
      entityID: entityID,
      mergeJSON: mergeJSON,
      transactionID: transactionID
    )
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

public struct CLISyncParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLISyncInvocation {
    guard let command = input.first else {
      throw CLISyncArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "inspect", "show", "status":
      try requireNoRemainingSyncArguments(&input, usage: CLISyncUsage.inspect)
      return .inspect

    case "mark-processed":
      let transactionID = try parseRequiredSyncArgument(
        from: &input, usage: CLISyncUsage.markProcessed)
      try requireNoRemainingSyncArguments(&input, usage: CLISyncUsage.markProcessed)
      return .markProcessed(transactionID: transactionID)

    default:
      throw CLISyncArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIAppParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAppInvocation {
    guard let command = input.first else {
      throw CLIAppArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "show", "status", "current":
      try requireNoRemainingAppArguments(&input, usage: CLIAppUsage.show)
      return .show

    case "select":
      let appID = try parseRequiredAppArgument(from: &input, usage: CLIAppUsage.select)
      try requireNoRemainingAppArguments(&input, usage: CLIAppUsage.select)
      return .select(appID: appID)

    case "ephemeral":
      return .ephemeral(try CLIAppEphemeralParser().parse(&input))

    default:
      throw CLIAppArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIAppEphemeralParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAppEphemeralInvocation {
    try CLIAppEphemeralOptionsParser().parse(&input)
  }
}

public struct CLIAppEphemeralOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAppEphemeralInvocation {
    var title: String?
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--title":
        guard let value = input.first else {
          throw CLIAppArgumentError.missingArguments(usage: CLIAppUsage.ephemeral)
        }
        input.removeFirst()
        title = value

      default:
        throw CLIAppArgumentError.unknownEphemeralOption(option)
      }
    }

    guard let title, !trimmed(title).isEmpty else {
      throw CLIAppArgumentError.missingArguments(usage: CLIAppUsage.ephemeral)
    }
    return CLIAppEphemeralInvocation(title: title)
  }
}

public struct CLICacheParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLICacheInvocation {
    guard let command = input.first else {
      throw CLICacheArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "inspect":
      try requireNoRemainingCacheArguments(&input, usage: CLICacheUsage.inspect)
      return .inspect

    case "attributes", "attrs":
      return .attributes(
        namespace: try parseOptionalCacheNamespace(from: &input, usage: CLICacheUsage.attributes)
      )

    case "triples", "facts":
      return .triples(
        namespace: try parseOptionalCacheNamespace(from: &input, usage: CLICacheUsage.triples)
      )

    default:
      throw CLICacheArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIOutboxParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIOutboxInvocation {
    guard let command = input.first else {
      throw CLIOutboxArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "inspect":
      try requireNoRemainingOutboxArguments(&input, usage: CLIOutboxUsage.inspect)
      return .inspect

    case "transport", "wire", "tx-steps":
      return .transport(includeFailed: try CLIOutboxTransportOptionsParser().parse(&input))

    case "flush", "send":
      return .flush(limit: try CLIOutboxFlushOptionsParser().parse(&input))

    case "confirm":
      let mutationID = try parseSingleOutboxArgument(from: &input, usage: CLIOutboxUsage.confirm)
      return .confirm(mutationID: mutationID)

    case "fail":
      let mutationID = try parseRequiredOutboxArgument(from: &input, usage: CLIOutboxUsage.fail)
      let message = input.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      input.removeAll()
      guard !message.isEmpty else {
        throw CLIOutboxArgumentError.missingArguments(usage: CLIOutboxUsage.fail)
      }
      return .fail(mutationID: mutationID, message: message)

    case "retry":
      let mutationID = try parseSingleOutboxArgument(from: &input, usage: CLIOutboxUsage.retry)
      return .retry(mutationID: mutationID)

    case "drain":
      return .drain(limit: try CLIOutboxDrainOptionsParser().parse(&input))

    default:
      throw CLIOutboxArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIOutboxTransportOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> Bool {
    var includeFailed = false

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--all":
        includeFailed = true

      default:
        throw CLIOutboxArgumentError.invalidArguments(usage: CLIOutboxUsage.transport)
      }
    }

    return includeFailed
  }
}

public struct CLIOutboxFlushOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> Int? {
    var limit: Int?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--limit":
        guard let value = input.first,
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIOutboxArgumentError.invalidArguments(usage: CLIOutboxUsage.flush)
        }
        input.removeFirst()
        limit = parsed

      default:
        throw CLIOutboxArgumentError.unknownOption(option, usage: CLIOutboxUsage.flush)
      }
    }

    return limit
  }
}

public struct CLIOutboxDrainOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> Int? {
    var sawLocalConfirm = false
    var limit: Int?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--local-confirm":
        sawLocalConfirm = true

      case "--limit":
        guard let value = input.first,
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIOutboxArgumentError.invalidArguments(usage: CLIOutboxUsage.drain)
        }
        input.removeFirst()
        limit = parsed

      default:
        throw CLIOutboxArgumentError.unknownOption(option, usage: CLIOutboxUsage.drain)
      }
    }

    guard sawLocalConfirm else {
      throw CLIOutboxArgumentError.missingArguments(usage: CLIOutboxUsage.drain)
    }
    return limit
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
    let parser = CLIRoomWatchOptionsParser(
      usageCommand: "instant-swift-data rooms presence watch <room-type> <room-id>",
      domain: "rooms presence watch"
    )
    let eventCount = try parser.parse(&input)
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
    let parser = CLIRoomWatchOptionsParser(
      usageCommand: "instant-swift-data rooms topics watch <room-type> <room-id> <topic>",
      domain: "rooms topics watch"
    )
    let eventCount = try parser.parse(&input)
    return CLIRoomTopicWatchInvocation(room: room, topic: topic, eventCount: eventCount)
  }
}

public struct CLIRoomWatchOptionsParser: Parser {
  public var usageCommand: String
  public var domain: String

  public init(usageCommand: String, domain: String) {
    self.usageCommand = usageCommand
    self.domain = domain
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> Int {
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
    CLIAuthWatchInvocation(eventCount: try CLIAuthWatchOptionsParser().parse(&input))
  }
}

public struct CLIAuthWatchOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> Int {
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
    CLIFilesWatchInvocation(eventCount: try CLIFilesWatchOptionsParser().parse(&input))
  }
}

public struct CLIFilesWatchOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> Int {
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

    case "create":
      return .create(try CLIStreamCreateParser().parse(&input))

    case "append-content", "write-content":
      return .appendContent(try CLIStreamAppendContentParser().parse(&input))

    case "close", "finish", "abort":
      return .close(try CLIStreamCloseParser().parse(&input))

    case "read-content", "read-bytes":
      return .readContent(try CLIStreamContentReadParser().parse(&input))

    case "watch-content", "watch-bytes":
      return .watchContent(try CLIStreamContentWatchParser().parse(&input))

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

public struct CLIStreamCreateParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamCreateInvocation {
    let clientID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.create)
    try requireNoRemainingStreamArguments(
      &input, domain: "streams create", usage: CLIStreamsUsage.create)
    return CLIStreamCreateInvocation(clientID: clientID)
  }
}

public struct CLIStreamAppendContentParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamAppendContentInvocation {
    let streamID = try parseRequiredStreamArgument(
      from: &input, usage: CLIStreamsUsage.appendContent)
    var content: String?
    var expectedOffset: Int64?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--content":
        content = try parseStreamOptionValue(
          from: &input,
          option: option,
          usage: CLIStreamsUsage.appendContent
        )

      case "--offset":
        let value = try parseStreamOptionValue(
          from: &input,
          option: option,
          usage: CLIStreamsUsage.appendContent
        )
        guard let parsed = Int64(value), parsed >= 0 else {
          throw CLIStreamsArgumentError.invalidOffset(
            option: option,
            value: value,
            usage: CLIStreamsUsage.appendContent
          )
        }
        expectedOffset = parsed

      default:
        throw CLIStreamsArgumentError.unknownOption(
          domain: "streams append-content",
          option: option,
          usage: CLIStreamsUsage.appendContent
        )
      }
    }

    guard let content else {
      throw CLIStreamsArgumentError.missingRequiredOption(
        option: "--content",
        usage: CLIStreamsUsage.appendContent
      )
    }
    return CLIStreamAppendContentInvocation(
      streamID: streamID,
      content: content,
      expectedOffset: expectedOffset
    )
  }
}

public struct CLIStreamCloseParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamCloseInvocation {
    let streamID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.close)
    var abortReason: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--abort-reason":
        abortReason = try parseStreamOptionValue(
          from: &input,
          option: option,
          usage: CLIStreamsUsage.close
        )

      default:
        throw CLIStreamsArgumentError.unknownOption(
          domain: "streams close",
          option: option,
          usage: CLIStreamsUsage.close
        )
      }
    }

    return CLIStreamCloseInvocation(streamID: streamID, abortReason: abortReason)
  }
}

public struct CLIStreamContentReadParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamContentReadInvocation {
    var selector: CLIStreamContentSelector?
    var byteOffset: Int64 = 0
    var eventCount: Int?
    try parseStreamContentOptions(
      from: &input,
      selector: &selector,
      byteOffset: &byteOffset,
      eventCount: &eventCount,
      domain: "streams read-content",
      usage: CLIStreamsUsage.readContent,
      eventUsageCommand: nil
    )
    guard let selector else {
      throw CLIStreamsArgumentError.missingArguments(usage: CLIStreamsUsage.readContent)
    }
    return CLIStreamContentReadInvocation(selector: selector, byteOffset: byteOffset)
  }
}

public struct CLIStreamContentWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamContentWatchInvocation {
    var selector: CLIStreamContentSelector?
    var byteOffset: Int64 = 0
    var eventCount: Int? = 1
    try parseStreamContentOptions(
      from: &input,
      selector: &selector,
      byteOffset: &byteOffset,
      eventCount: &eventCount,
      domain: "streams watch-content",
      usage: CLIStreamsUsage.watchContent,
      eventUsageCommand: "instant-swift-data streams watch-content <stream-id>"
    )
    guard let selector else {
      throw CLIStreamsArgumentError.missingArguments(usage: CLIStreamsUsage.watchContent)
    }
    return CLIStreamContentWatchInvocation(
      selector: selector,
      byteOffset: byteOffset,
      eventCount: eventCount ?? 1
    )
  }
}

public struct CLIStreamReadParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamReadInvocation {
    let streamID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.read)
    var limit: Int?
    var afterIndex: Int64?
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

      case "--after-index":
        let value = try parseStreamOptionValue(
          from: &input,
          option: option,
          usage: CLIStreamsUsage.read
        )
        guard let parsed = Int64(value), parsed >= 0 else {
          throw CLIStreamsArgumentError.invalidAfterIndex(value, usage: CLIStreamsUsage.read)
        }
        afterIndex = parsed

      default:
        throw CLIStreamsArgumentError.unknownOption(
          domain: "streams read",
          option: option,
          usage: CLIStreamsUsage.read
        )
      }
    }
    return CLIStreamReadInvocation(streamID: streamID, limit: limit, afterIndex: afterIndex)
  }
}

public struct CLIStreamWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamWatchInvocation {
    let streamID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.watch)
    let options = try CLIStreamWatchInvocationOptionsParser().parse(&input)
    return CLIStreamWatchInvocation(
      streamID: streamID,
      eventCount: options.eventCount,
      afterIndex: options.afterIndex
    )
  }
}

public struct CLIStreamWatchOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> Int {
    let options = try CLIStreamWatchInvocationOptionsParser().parse(&input)
    return options.eventCount
  }
}

public struct CLIStreamWatchInvocationOptionsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamWatchOptionsInvocation {
    let usageCommand = "instant-swift-data streams watch <stream-id>"
    var eventCount = 1
    var afterIndex: Int64?

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

      case "--after-index":
        let value = try parseStreamOptionValue(
          from: &input,
          option: option,
          usage: CLIStreamsUsage.watch
        )
        guard let parsed = Int64(value), parsed >= 0 else {
          throw CLIStreamsArgumentError.invalidAfterIndex(value, usage: CLIStreamsUsage.watch)
        }
        afterIndex = parsed

      default:
        throw CLIStreamsArgumentError.unknownOption(
          domain: "streams watch",
          option: option,
          usage: CLIStreamsUsage.watch
        )
      }
    }

    return CLIStreamWatchOptionsInvocation(eventCount: eventCount, afterIndex: afterIndex)
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
    "Usage: \(usageCommand) [--suite <local-todos|cross-sdk-core>] [--iterations n] [--app-id id] [--json|--jsonl]"
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

public enum CLIValidationRunnerArguments {
  public static func parse(_ arguments: [String]) throws -> CLIValidationRunnerInvocation {
    var input = arguments[...]
    return try CLIValidationRunnerParser().parse(&input)
  }
}

public enum CLIAdminArguments {
  public static func firstMergeJSONAfterValidTransactHead(_ arguments: [String]) -> String? {
    var input = arguments[...]
    guard let command = input.first, command == "transact" || command == "tx" else {
      return nil
    }
    input.removeFirst()

    guard let rawNamespace = input.first else { return nil }
    input.removeFirst()
    let namespace = trimmed(rawNamespace)
    guard isValidAdminPathComponent(namespace) else { return nil }

    guard let rawEntityID = input.first else { return nil }
    input.removeFirst()
    let entityID = trimmed(rawEntityID)
    guard !entityID.isEmpty else { return nil }

    var sawTransactionID = false
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--merge":
        guard let mergeJSON = input.first else { return nil }
        return mergeJSON

      case "--transaction-id":
        guard !sawTransactionID, let rawTransactionID = input.first else {
          return nil
        }
        input.removeFirst()
        guard !trimmed(rawTransactionID).isEmpty else { return nil }
        sawTransactionID = true

      default:
        return nil
      }
    }
    return nil
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

private func requireNoRemainingAuthArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIAuthArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseRawAuthRecipeArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesAuthArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  guard !trimmed(value).isEmpty else {
    throw CLIExamplesAuthArgumentError.invalidArguments(usage: usage)
  }
  return value
}

private func parseAuthRecipeOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesAuthArgumentError.missingValue(option: option, usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesAuthArgumentError.missingValue(option: option, usage: usage)
  }
  return trimmedValue
}

private func requireNoRemainingExamplesAuthArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIExamplesAuthArgumentError.unknownOption(
      domain: "examples auth",
      option: argument,
      usage: usage
    )
  }
}

private func parseRequiredAppBuilderArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesAppBuilderArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIExamplesAppBuilderArgumentError.invalidArguments(usage: usage)
  }
  return parsed
}

private func parseAppBuilderOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesAppBuilderArgumentError.missingValue(option: option, usage: usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIExamplesAppBuilderArgumentError.missingValue(option: option, usage: usage)
  }
  return parsed
}

private func requireNoRemainingExamplesAppBuilderArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIExamplesAppBuilderArgumentError.unknownOption(option: argument, usage: usage)
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

private func parseStreamContentOptions(
  from input: inout ArraySlice<String>,
  selector: inout CLIStreamContentSelector?,
  byteOffset: inout Int64,
  eventCount: inout Int?,
  domain: String,
  usage: String,
  eventUsageCommand: String?
) throws {
  while let argument = input.first {
    input.removeFirst()
    switch argument {
    case "--stream-id":
      let value = try parseNonEmptyStreamOptionValue(
        from: &input,
        option: argument,
        usage: usage
      )
      try setStreamContentSelector(.streamID(value), selector: &selector, usage: usage)

    case "--client-id":
      let value = try parseNonEmptyStreamOptionValue(
        from: &input,
        option: argument,
        usage: usage
      )
      try setStreamContentSelector(.clientID(value), selector: &selector, usage: usage)

    case "--byte-offset":
      let value = try parseStreamOptionValue(from: &input, option: argument, usage: usage)
      guard let parsed = Int64(value), parsed >= 0 else {
        throw CLIStreamsArgumentError.invalidOffset(
          option: argument,
          value: value,
          usage: usage
        )
      }
      byteOffset = parsed

    case "--events":
      guard eventCount != nil, let eventUsageCommand else {
        throw CLIStreamsArgumentError.unknownOption(
          domain: domain,
          option: argument,
          usage: usage
        )
      }
      let value = try parseStreamOptionValue(
        from: &input,
        option: argument,
        usage: "Usage: \(eventUsageCommand) --events 1"
      )
      guard let parsed = Int(value), parsed == 1 else {
        throw CLIStreamsArgumentError.invalidEventCount(value, usageCommand: eventUsageCommand)
      }
      eventCount = parsed

    default:
      guard !argument.hasPrefix("-") else {
        throw CLIStreamsArgumentError.unknownOption(
          domain: domain,
          option: argument,
          usage: usage
        )
      }
      let value = trimmed(argument)
      guard !value.isEmpty else {
        throw CLIStreamsArgumentError.missingArguments(usage: usage)
      }
      try setStreamContentSelector(.streamID(value), selector: &selector, usage: usage)
    }
  }
}

private func setStreamContentSelector(
  _ nextSelector: CLIStreamContentSelector,
  selector: inout CLIStreamContentSelector?,
  usage: String
) throws {
  guard selector == nil else {
    throw CLIStreamsArgumentError.missingArguments(usage: usage)
  }
  selector = nextSelector
}

private func parseNonEmptyStreamOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  let value = trimmed(try parseStreamOptionValue(from: &input, option: option, usage: usage))
  guard !value.isEmpty else {
    throw CLIStreamsArgumentError.missingArguments(usage: usage)
  }
  return value
}

private func requireNoRemainingStreamArguments(
  _ input: inout ArraySlice<String>,
  domain: String,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIStreamsArgumentError.unknownOption(
      domain: domain,
      option: argument,
      usage: usage
    )
  }
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

private func parseRequiredAdminNamespace(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIAdminArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  let namespace = trimmed(value)
  guard isValidAdminPathComponent(namespace) else {
    throw CLIAdminArgumentError.invalidNamespace(usage: usage)
  }
  return namespace
}

private func parseRequiredAdminEntityID(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIAdminArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  let entityID = trimmed(value)
  guard !entityID.isEmpty else {
    throw CLIAdminArgumentError.invalidEntityID(usage: usage)
  }
  return entityID
}

private func isValidAdminPathComponent(_ value: String) -> Bool {
  !value.isEmpty
    && !value.contains("/")
    && !value.contains(where: { $0.isWhitespace })
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

private func parseRequiredSyncArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLISyncArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  guard !trimmed(value).isEmpty else {
    throw CLISyncArgumentError.missingArguments(usage: usage)
  }
  return value
}

private func requireNoRemainingSyncArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLISyncArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseRequiredAppArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIAppArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  guard !trimmed(value).isEmpty else {
    throw CLIAppArgumentError.missingArguments(usage: usage)
  }
  return value
}

private func requireNoRemainingAppArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIAppArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseOptionalCacheNamespace(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String? {
  guard let value = input.first else { return nil }
  input.removeFirst()
  try requireNoRemainingCacheArguments(&input, usage: usage)
  let namespace = trimmed(value)
  guard isValidCacheNamespace(namespace) else {
    throw CLICacheArgumentError.invalidNamespace(namespace, usage: usage)
  }
  return namespace
}

private func requireNoRemainingCacheArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLICacheArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func isValidCacheNamespace(_ value: String) -> Bool {
  !value.isEmpty
    && !value.contains("/")
    && !value.contains(where: { $0.isWhitespace })
}

private func parseSingleOutboxArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredOutboxArgument(from: &input, usage: usage)
  try requireNoRemainingOutboxArguments(&input, usage: usage)
  return value
}

private func parseRequiredOutboxArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIOutboxArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  return value
}

private func requireNoRemainingOutboxArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIOutboxArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func requireSchemaCommand(
  _ command: String,
  from input: inout ArraySlice<String>,
  usage: String
) throws {
  guard input.first == command else {
    throw CLISchemaArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
}

private func requirePermissionsCommand(
  _ command: String,
  from input: inout ArraySlice<String>,
  usage: String
) throws {
  guard input.first == command else {
    throw CLIPermissionsArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
}

private func parseSingleExamplesTodosArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredExamplesTodosArgument(from: &input, usage: usage)
  try requireNoRemainingExamplesTodosArguments(&input, usage: usage)
  return value
}

private func parseRequiredExamplesTodosArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesTodosArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  return value
}

private func parseExamplesTodosNonNegativeInt(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> Int {
  guard let value = input.first,
    let parsed = Int(value),
    parsed >= 0
  else {
    throw CLIExamplesTodosArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  return parsed
}

private func parseExamplesTodosCursor(
  from input: inout ArraySlice<String>,
  option: String,
  inclusive: Bool,
  usageCommand: String
) throws -> CLIQueryCursor {
  guard let value = input.first else {
    throw CLIExamplesTodosArgumentError.invalidArguments(
      usage: "Usage: \(usageCommand) \(option) id"
    )
  }
  input.removeFirst()
  let entityID = trimmed(value)
  guard !entityID.isEmpty else {
    throw CLIExamplesTodosArgumentError.invalidArguments(
      usage: "Usage: \(usageCommand) \(option) id"
    )
  }
  return CLIQueryCursor(entityID: entityID, inclusive: inclusive)
}

private func requireNoRemainingExamplesTodosArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesTodosArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesTodoLinksArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesTodoLinksArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesCountersArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesCountersArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesChatArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesChatArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesMicroblogArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesMicroblogArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesMobileChatArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesMobileChatArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesStroopwafelArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesStroopwafelArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesTypingIndicatorArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(usage: usage)
  }
}

private func requireNoRemainingExamplesAvatarStackArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesAvatarStackArgumentError.invalidArguments(usage: usage)
  }
}

private func parseSingleExamplesTypingIndicatorUserID(
  from input: inout ArraySlice<String>
) throws -> String {
  let userID = try parseRequiredExamplesTypingIndicatorArgument(
    from: &input,
    usage: CLIExamplesTypingIndicatorUsage.user
  )
  try requireNoRemainingExamplesTypingIndicatorArguments(
    &input,
    usage: CLIExamplesTypingIndicatorUsage.user
  )
  return userID
}

private func parseRequiredExamplesTypingIndicatorArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseSingleExamplesAvatarStackUserID(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let userID = try parseRequiredExamplesAvatarStackArgument(
    from: &input,
    usage: usage
  )
  try requireNoRemainingExamplesAvatarStackArguments(
    &input,
    usage: usage
  )
  return userID
}

private func parseRequiredExamplesAvatarStackArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesAvatarStackArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesAvatarStackArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseExamplesAvatarStackJoinOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesAvatarStackJoinInvocation {
  let userID = try parseRequiredExamplesAvatarStackArgument(
    from: &input,
    usage: CLIExamplesAvatarStackUsage.join
  )
  var invocation = CLIExamplesAvatarStackJoinInvocation(userID: userID)
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--name":
      invocation.name = try parseRequiredExamplesAvatarStackArgument(
        from: &input,
        usage: CLIExamplesAvatarStackUsage.join
      )

    default:
      throw CLIExamplesAvatarStackArgumentError.invalidArguments(
        usage: CLIExamplesAvatarStackUsage.join
      )
    }
  }
  return invocation
}

private func parseExamplesAvatarStackListOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesAvatarStackListInvocation {
  var invocation = CLIExamplesAvatarStackListInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesAvatarStackArgument(
        from: &input,
        usage: CLIExamplesAvatarStackUsage.list
      )

    default:
      throw CLIExamplesAvatarStackArgumentError.invalidArguments(
        usage: CLIExamplesAvatarStackUsage.list
      )
    }
  }
  return invocation
}

private func parseExamplesAvatarStackWatchOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesAvatarStackWatchInvocation {
  var invocation = CLIExamplesAvatarStackWatchInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      guard let value = input.first,
        let parsed = Int(value),
        parsed == 1
      else {
        throw CLIExamplesAvatarStackArgumentError.invalidArguments(
          usage: CLIExamplesAvatarStackUsage.watch
        )
      }
      input.removeFirst()
      invocation.eventCount = parsed

    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesAvatarStackArgument(
        from: &input,
        usage: CLIExamplesAvatarStackUsage.watch
      )

    default:
      throw CLIExamplesAvatarStackArgumentError.invalidArguments(
        usage: CLIExamplesAvatarStackUsage.watch
      )
    }
  }
  return invocation
}

private func parseExamplesCursorsLeaf(
  from input: inout ArraySlice<String>,
  rootUsage: String,
  moveUsage: String,
  listUsage: String,
  watchUsage: String,
  userUsage: String,
  allowsName: Bool
) throws -> CLIExamplesCursorsLeafInvocation {
  guard let command = input.first else {
    throw CLIExamplesCursorsArgumentError.invalidArguments(usage: rootUsage)
  }
  input.removeFirst()

  switch command {
  case "move", "set":
    return .move(
      try parseExamplesCursorsMoveOptions(
        from: &input,
        usage: moveUsage,
        allowsName: allowsName
      )
    )

  case "list", "presence":
    return .list(try parseExamplesCursorsListOptions(from: &input, usage: listUsage))

  case "watch", "observe":
    return .watch(try parseExamplesCursorsWatchOptions(from: &input, usage: watchUsage))

  case "clear", "hide":
    return .clear(
      userID: try parseSingleExamplesCursorsUserID(from: &input, usage: userUsage)
    )

  case "leave":
    return .leave(
      userID: try parseSingleExamplesCursorsUserID(from: &input, usage: userUsage)
    )

  default:
    input.removeAll()
    return .unknown(command)
  }
}

private func parseExamplesCursorsMoveOptions(
  from input: inout ArraySlice<String>,
  usage: String,
  allowsName: Bool
) throws -> CLIExamplesCursorsMoveInvocation {
  let userID = try parseRequiredExamplesCursorsArgument(from: &input, usage: usage)
  var x: Double?
  var y: Double?
  var xPercent: Double?
  var yPercent: Double?
  var color: String?
  var name: String?

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--x":
      x = try parseRequiredExamplesCursorsDouble(from: &input, usage: usage)

    case "--y":
      y = try parseRequiredExamplesCursorsDouble(from: &input, usage: usage)

    case "--x-percent":
      xPercent = try parseRequiredExamplesCursorsDouble(from: &input, usage: usage)

    case "--y-percent":
      yPercent = try parseRequiredExamplesCursorsDouble(from: &input, usage: usage)

    case "--color":
      color = try parseRequiredExamplesCursorsArgument(from: &input, usage: usage)

    case "--name" where allowsName:
      name = try parseRequiredExamplesCursorsArgument(from: &input, usage: usage)

    default:
      throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
    }
  }

  guard let x, let y, let xPercent, let yPercent else {
    throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
  }
  return CLIExamplesCursorsMoveInvocation(
    userID: userID,
    x: x,
    y: y,
    xPercent: xPercent,
    yPercent: yPercent,
    color: color,
    name: name
  )
}

private func parseExamplesCursorsListOptions(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> CLIExamplesCursorsListInvocation {
  var invocation = CLIExamplesCursorsListInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesCursorsArgument(
        from: &input,
        usage: usage
      )

    default:
      throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
    }
  }
  return invocation
}

private func parseExamplesCursorsWatchOptions(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> CLIExamplesCursorsWatchInvocation {
  var invocation = CLIExamplesCursorsWatchInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      guard let value = input.first,
        let parsed = Int(value),
        parsed == 1
      else {
        throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
      }
      input.removeFirst()
      invocation.eventCount = parsed

    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesCursorsArgument(
        from: &input,
        usage: usage
      )

    default:
      throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
    }
  }
  return invocation
}

private func parseSingleExamplesCursorsUserID(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let userID = try parseRequiredExamplesCursorsArgument(from: &input, usage: usage)
  if !input.isEmpty {
    throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
  }
  return userID
}

private func parseRequiredExamplesCursorsArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseRequiredExamplesCursorsDouble(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> Double {
  let value = try parseRequiredExamplesCursorsArgument(from: &input, usage: usage)
  guard let parsed = Double(value), parsed.isFinite else {
    throw CLIExamplesCursorsArgumentError.invalidArguments(usage: usage)
  }
  return parsed
}

private func parseExamplesMergeTileGameJoinOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesMergeTileGameJoinInvocation {
  let userID = try parseRequiredExamplesMergeTileGameArgument(
    from: &input,
    usage: CLIExamplesMergeTileGameUsage.join
  )
  var color: String?
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--color":
      color = try parseRequiredExamplesMergeTileGameArgument(
        from: &input,
        usage: CLIExamplesMergeTileGameUsage.join
      )

    default:
      throw CLIExamplesMergeTileGameArgumentError.invalidArguments(
        usage: CLIExamplesMergeTileGameUsage.join
      )
    }
  }
  return CLIExamplesMergeTileGameJoinInvocation(userID: userID, color: color)
}

private func parseExamplesMergeTileGameTapOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesMergeTileGameTapInvocation {
  let userID = try parseRequiredExamplesMergeTileGameArgument(
    from: &input,
    usage: CLIExamplesMergeTileGameUsage.tap
  )
  let row = try parseRequiredExamplesMergeTileGameCellIndex(
    from: &input,
    usage: CLIExamplesMergeTileGameUsage.tap
  )
  let column = try parseRequiredExamplesMergeTileGameCellIndex(
    from: &input,
    usage: CLIExamplesMergeTileGameUsage.tap
  )
  var color: String?
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--color":
      color = try parseRequiredExamplesMergeTileGameArgument(
        from: &input,
        usage: CLIExamplesMergeTileGameUsage.tap
      )

    default:
      throw CLIExamplesMergeTileGameArgumentError.invalidArguments(
        usage: CLIExamplesMergeTileGameUsage.tap
      )
    }
  }
  return CLIExamplesMergeTileGameTapInvocation(
    userID: userID,
    row: row,
    column: column,
    color: color
  )
}

private func parseExamplesMergeTileGameBoardOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesMergeTileGameBoardInvocation {
  var invocation = CLIExamplesMergeTileGameBoardInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesMergeTileGameArgument(
        from: &input,
        usage: CLIExamplesMergeTileGameUsage.board
      )

    default:
      throw CLIExamplesMergeTileGameArgumentError.invalidArguments(
        usage: CLIExamplesMergeTileGameUsage.board
      )
    }
  }
  return invocation
}

private func parseExamplesMergeTileGameWatchOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesMergeTileGameWatchInvocation {
  var invocation = CLIExamplesMergeTileGameWatchInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      guard let value = input.first,
        let parsed = Int(value),
        parsed == 1
      else {
        throw CLIExamplesMergeTileGameArgumentError.invalidArguments(
          usage: CLIExamplesMergeTileGameUsage.watch
        )
      }
      input.removeFirst()
      invocation.eventCount = parsed

    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesMergeTileGameArgument(
        from: &input,
        usage: CLIExamplesMergeTileGameUsage.watch
      )

    default:
      throw CLIExamplesMergeTileGameArgumentError.invalidArguments(
        usage: CLIExamplesMergeTileGameUsage.watch
      )
    }
  }
  return invocation
}

private func parseSingleExamplesMergeTileGameUserID(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let userID = try parseRequiredExamplesMergeTileGameArgument(from: &input, usage: usage)
  if !input.isEmpty {
    throw CLIExamplesMergeTileGameArgumentError.invalidArguments(usage: usage)
  }
  return userID
}

private func parseRequiredExamplesMergeTileGameArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesMergeTileGameArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesMergeTileGameArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseRequiredExamplesMergeTileGameCellIndex(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> Int {
  let value = try parseRequiredExamplesMergeTileGameArgument(from: &input, usage: usage)
  guard let parsed = Int(value), (0..<4).contains(parsed) else {
    throw CLIExamplesMergeTileGameArgumentError.invalidArguments(usage: usage)
  }
  return parsed
}

private func requireNoRemainingExamplesMergeTileGameArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesMergeTileGameArgumentError.invalidArguments(usage: usage)
  }
}

private func parseExamplesTypingIndicatorListOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesTypingIndicatorListInvocation {
  var invocation = CLIExamplesTypingIndicatorListInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesTypingIndicatorArgument(
        from: &input,
        usage: CLIExamplesTypingIndicatorUsage.list
      )

    default:
      throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(
        usage: CLIExamplesTypingIndicatorUsage.list
      )
    }
  }
  return invocation
}

private func parseExamplesTypingIndicatorWatchOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesTypingIndicatorWatchInvocation {
  var invocation = CLIExamplesTypingIndicatorWatchInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      guard let value = input.first,
        let parsed = Int(value),
        parsed == 1
      else {
        throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(
          usage: CLIExamplesTypingIndicatorUsage.watch
        )
      }
      input.removeFirst()
      invocation.eventCount = parsed

    case "--viewer-user-id":
      invocation.viewerUserID = try parseRequiredExamplesTypingIndicatorArgument(
        from: &input,
        usage: CLIExamplesTypingIndicatorUsage.watch
      )

    default:
      throw CLIExamplesTypingIndicatorArgumentError.invalidArguments(
        usage: CLIExamplesTypingIndicatorUsage.watch
      )
    }
  }
  return invocation
}

private func parseExamplesReactionsTapOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesReactionsTapInvocation {
  let name = try parseRequiredExamplesReactionsArgument(
    from: &input,
    usage: CLIExamplesReactionsUsage.tap
  )
  guard examplesReactionsAllowedNames.contains(name) else {
    throw CLIExamplesReactionsArgumentError.invalidReactionName(
      name,
      usage: CLIExamplesReactionsUsage.tap
    )
  }

  var invocation = CLIExamplesReactionsTapInvocation(name: name)
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--direction", "--direction-angle":
      invocation.directionAngle = try parseExamplesReactionsAngle(
        from: &input,
        usage: CLIExamplesReactionsUsage.tap
      )

    case "--rotation", "--rotation-angle":
      invocation.rotationAngle = try parseExamplesReactionsAngle(
        from: &input,
        usage: CLIExamplesReactionsUsage.tap
      )

    case "--user-id":
      invocation.userID = try parseRequiredExamplesReactionsArgument(
        from: &input,
        usage: CLIExamplesReactionsUsage.tap
      )

    default:
      if option.hasPrefix("--") {
        throw CLIExamplesReactionsArgumentError.unknownTapOption(
          option,
          usage: CLIExamplesReactionsUsage.tap
        )
      }
      throw CLIExamplesReactionsArgumentError.invalidArguments(
        usage: CLIExamplesReactionsUsage.tap
      )
    }
  }

  return invocation
}

private func parseExamplesReactionsListOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesReactionsListInvocation {
  var invocation = CLIExamplesReactionsListInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--limit":
      invocation.limit = try parseExamplesReactionsNonNegativeInt(
        from: &input,
        usage: CLIExamplesReactionsUsage.list
      )

    default:
      throw CLIExamplesReactionsArgumentError.invalidArguments(
        usage: CLIExamplesReactionsUsage.list
      )
    }
  }
  return invocation
}

private func parseExamplesReactionsWatchOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesReactionsWatchInvocation {
  var invocation = CLIExamplesReactionsWatchInvocation()
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      guard let value = input.first,
        let parsed = Int(value),
        parsed == 1
      else {
        throw CLIExamplesReactionsArgumentError.invalidArguments(
          usage: CLIExamplesReactionsUsage.watch
        )
      }
      input.removeFirst()
      invocation.eventCount = parsed

    default:
      throw CLIExamplesReactionsArgumentError.invalidArguments(
        usage: CLIExamplesReactionsUsage.watch
      )
    }
  }
  return invocation
}

private let examplesReactionsAllowedNames = ["fire", "wave", "confetti", "heart"]

private func parseRequiredExamplesReactionsArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesReactionsArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesReactionsArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseExamplesReactionsAngle(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> Double {
  guard let value = input.first else {
    throw CLIExamplesReactionsArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  guard let parsed = Double(value),
    parsed.isFinite,
    parsed >= 0,
    parsed < 360
  else {
    throw CLIExamplesReactionsArgumentError.invalidAngle(value, usage: usage)
  }
  return parsed
}

private func parseExamplesReactionsNonNegativeInt(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> Int {
  guard let value = input.first,
    let parsed = Int(value),
    parsed >= 0
  else {
    throw CLIExamplesReactionsArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  return parsed
}

private func parseExamplesCountersAddOptions(
  _ input: inout ArraySlice<String>
) throws -> Int {
  var count = 0

  while let option = input.first {
    switch option {
    case "--count":
      input.removeFirst()
      guard let value = input.first, let parsed = Int(value) else {
        throw CLIExamplesCountersArgumentError.invalidArguments(
          usage: CLIExamplesCountersUsage.add
        )
      }
      input.removeFirst()
      count = parsed

    default:
      throw CLIExamplesCountersArgumentError.invalidArguments(
        usage: CLIExamplesCountersUsage.add
      )
    }
  }

  return count
}

private func parseRequiredExamplesChatArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesChatArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesChatArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseExamplesChatPostOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesChatPostInvocation {
  let channelID = try parseRequiredExamplesChatArgument(
    from: &input,
    usage: CLIExamplesChatUsage.post
  )
  var authorName: String?
  var textParts: [String] = []

  while let value = input.first {
    input.removeFirst()
    switch value {
    case "--author":
      guard let rawAuthorName = input.first else {
        throw CLIExamplesChatArgumentError.invalidArguments(
          usage: CLIExamplesChatUsage.post
        )
      }
      input.removeFirst()
      let trimmedAuthorName = trimmed(rawAuthorName)
      guard !trimmedAuthorName.isEmpty else {
        throw CLIExamplesChatArgumentError.invalidArguments(
          usage: CLIExamplesChatUsage.post
        )
      }
      authorName = trimmedAuthorName

    default:
      if value.hasPrefix("--") {
        throw CLIExamplesChatArgumentError.unknownPostOption(
          value,
          usage: CLIExamplesChatUsage.post
        )
      }
      textParts.append(value)
    }
  }

  let text = textParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  guard !text.isEmpty else {
    throw CLIExamplesChatArgumentError.invalidArguments(
      usage: CLIExamplesChatUsage.post
    )
  }

  return CLIExamplesChatPostInvocation(
    channelID: channelID,
    text: text,
    authorName: authorName
  )
}

private func parseRequiredExamplesMicroblogArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesMicroblogArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesMicroblogArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseSingleExamplesMicroblogArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredExamplesMicroblogArgument(from: &input, usage: usage)
  try requireNoRemainingExamplesMicroblogArguments(&input, usage: usage)
  return value
}

private func parseExamplesMicroblogPostOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesMicroblogPostInvocation {
  var color = "bg-blue-100"
  var contentParts: [String] = []

  while let value = input.first {
    input.removeFirst()
    switch value {
    case "--color":
      guard let rawColor = input.first else {
        throw CLIExamplesMicroblogArgumentError.invalidArguments(
          usage: CLIExamplesMicroblogUsage.post
        )
      }
      input.removeFirst()
      let trimmedColor = trimmed(rawColor)
      guard !trimmedColor.isEmpty else {
        throw CLIExamplesMicroblogArgumentError.invalidArguments(
          usage: CLIExamplesMicroblogUsage.post
        )
      }
      color = trimmedColor

    default:
      if value.hasPrefix("--") {
        throw CLIExamplesMicroblogArgumentError.unknownPostOption(
          value,
          usage: CLIExamplesMicroblogUsage.post
        )
      }
      contentParts.append(value)
    }
  }

  let content = contentParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  guard !content.isEmpty else {
    throw CLIExamplesMicroblogArgumentError.invalidArguments(
      usage: CLIExamplesMicroblogUsage.post
    )
  }

  return CLIExamplesMicroblogPostInvocation(content: content, color: color)
}

private func parseRequiredExamplesMobileChatArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesMobileChatArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesMobileChatArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseSingleExamplesMobileChatArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredExamplesMobileChatArgument(from: &input, usage: usage)
  try requireNoRemainingExamplesMobileChatArguments(&input, usage: usage)
  return value
}

private func parseExamplesMobileChatSendOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesMobileChatSendInvocation {
  let channelID = try parseRequiredExamplesMobileChatArgument(
    from: &input,
    usage: CLIExamplesMobileChatUsage.send
  )
  var contentParts: [String] = []

  while let value = input.first {
    input.removeFirst()
    if value.hasPrefix("--") {
      throw CLIExamplesMobileChatArgumentError.unknownSendOption(
        value,
        usage: CLIExamplesMobileChatUsage.send
      )
    }
    contentParts.append(value)
  }

  let content = contentParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  guard !content.isEmpty else {
    throw CLIExamplesMobileChatArgumentError.invalidArguments(
      usage: CLIExamplesMobileChatUsage.send
    )
  }

  return CLIExamplesMobileChatSendInvocation(channelID: channelID, content: content)
}

private func parseRequiredExamplesStroopwafelArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesStroopwafelArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIExamplesStroopwafelArgumentError.invalidArguments(usage: usage)
  }
  return trimmedValue
}

private func parseSingleExamplesStroopwafelArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredExamplesStroopwafelArgument(from: &input, usage: usage)
  try requireNoRemainingExamplesStroopwafelArguments(&input, usage: usage)
  return value
}

private func parseExamplesSyncUpsListOptions(
  from input: inout ArraySlice<String>,
  command: String
) throws -> CLIExamplesSyncUpsListInvocation {
  var invocation = CLIExamplesSyncUpsListInvocation(
    event: command == "refresh" ? "refresh" : "list"
  )

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--refresh":
      invocation.event = "refresh"

    case "--sync-up-id":
      guard let value = input.first, !value.isEmpty else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.list)
      }
      input.removeFirst()
      invocation.syncUpID = value

    default:
      throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.list)
    }
  }

  return invocation
}

private func parseExamplesSyncUpsAddOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesSyncUpsAddInvocation {
  guard let rawTitle = input.first else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.add)
  }
  input.removeFirst()
  let title = trimmed(rawTitle)
  guard !title.isEmpty else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.add)
  }

  var seconds = 60 * 5
  var theme = "bubblegum"
  var attendeeNames: [String] = []

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--seconds":
      seconds = try parseExamplesSyncUpsPositiveInt(from: &input)

    case "--theme":
      theme = try parseExamplesSyncUpsThemeRawValue(from: &input)

    case "--attendee":
      guard let value = input.first else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments(
          #"Usage: instant-swift-data examples sync-ups add "title" --attendee name"#
        )
      }
      input.removeFirst()
      let name = trimmed(value)
      if !name.isEmpty {
        attendeeNames.append(name)
      }

    default:
      throw CLIExamplesSyncUpsArgumentError.invalidArguments(
        "Unknown sync-ups add option: \(option). \(CLIExamplesSyncUpsUsage.syncUps)"
      )
    }
  }

  guard !attendeeNames.isEmpty else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(
      "Sync-ups require at least one --attendee name."
    )
  }

  return CLIExamplesSyncUpsAddInvocation(
    title: title,
    seconds: seconds,
    theme: theme,
    attendeeNames: attendeeNames
  )
}

private func parseExamplesSyncUpsUpdateOptions(
  from input: inout ArraySlice<String>,
  command: String
) throws -> CLIExamplesSyncUpsUpdateInvocation {
  let syncUpID = try parseRequiredExamplesSyncUpsArgument(
    from: &input,
    usage: CLIExamplesSyncUpsUsage.edit
  )

  var invocation = CLIExamplesSyncUpsUpdateInvocation(
    event: command == "edit" ? "edit" : "update",
    syncUpID: syncUpID
  )
  var didChange = false

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--title":
      guard let rawValue = input.first else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments("Sync-up title must not be empty.")
      }
      input.removeFirst()
      let value = trimmed(rawValue)
      guard !value.isEmpty else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments("Sync-up title must not be empty.")
      }
      invocation.title = value
      didChange = true

    case "--seconds":
      invocation.seconds = try parseExamplesSyncUpsPositiveInt(from: &input)
      didChange = true

    case "--theme":
      invocation.theme = try parseExamplesSyncUpsThemeRawValue(from: &input)
      didChange = true

    case "--attendee":
      guard let value = input.first else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments(
          "Usage: instant-swift-data examples sync-ups edit <sync-up-id> --attendee name"
        )
      }
      input.removeFirst()
      let name = trimmed(value)
      if invocation.replacementAttendeeNames == nil {
        invocation.replacementAttendeeNames = []
      }
      if !name.isEmpty {
        invocation.replacementAttendeeNames?.append(name)
      }
      didChange = true

    default:
      throw CLIExamplesSyncUpsArgumentError.invalidArguments(
        "Unknown sync-ups update option: \(option). \(CLIExamplesSyncUpsUsage.syncUps)"
      )
    }
  }

  guard didChange else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.edit)
  }
  if let replacementAttendeeNames = invocation.replacementAttendeeNames,
    replacementAttendeeNames.isEmpty
  {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(
      "Sync-up attendee replacement requires at least one non-empty --attendee."
    )
  }

  return invocation
}

private func parseExamplesSyncUpsRecordOptions(
  from input: inout ArraySlice<String>
) throws -> (syncUpID: String, transcript: String) {
  let syncUpID = try parseRequiredExamplesSyncUpsArgument(
    from: &input,
    usage: CLIExamplesSyncUpsUsage.record
  )
  var transcriptParts: [String] = []

  while let value = input.first {
    input.removeFirst()
    if value == "--transcript" {
      guard let transcript = input.first else {
        throw CLIExamplesSyncUpsArgumentError.invalidArguments(
          CLIExamplesSyncUpsUsage.recordTranscript
        )
      }
      input.removeFirst()
      transcriptParts.append(transcript)
    } else {
      transcriptParts.append(value)
    }
  }

  let transcript = transcriptParts.joined(separator: " ").trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard !transcript.isEmpty else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(CLIExamplesSyncUpsUsage.record)
  }
  return (syncUpID, transcript)
}

private func parseSingleExamplesSyncUpsArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredExamplesSyncUpsArgument(from: &input, usage: usage)
  try requireNoRemainingExamplesSyncUpsArguments(&input, usage: usage)
  return value
}

private func parseRequiredExamplesSyncUpsArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(usage)
  }
  input.removeFirst()
  return value
}

private func parseExamplesSyncUpsPositiveInt(
  from input: inout ArraySlice<String>
) throws -> Int {
  guard let value = input.first,
    let parsed = Int(value),
    parsed > 0
  else {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(
      "Sync-up seconds must be a positive integer."
    )
  }
  input.removeFirst()
  return parsed
}

private func parseExamplesSyncUpsThemeRawValue(
  from input: inout ArraySlice<String>
) throws -> String {
  guard let value = input.first, !value.hasPrefix("--") else {
    throw CLIExamplesSyncUpsArgumentError.invalidTheme
  }
  input.removeFirst()
  return value
}

private func requireNoRemainingExamplesSyncUpsArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesSyncUpsArgumentError.invalidArguments(usage)
  }
}

private func parseExamplesRemindersListOptions(
  from input: inout ArraySlice<String>,
  command: String
) throws -> CLIExamplesRemindersListInvocation {
  var invocation = CLIExamplesRemindersListInvocation(
    event: command == "refresh" ? "refresh" : "list"
  )
  var didSetCompleted = false

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--refresh":
      invocation.event = "refresh"

    case "--list-id":
      invocation.listID = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.list
      )

    case "--completed":
      guard let value = input.first, let parsed = parseCLIQueryBool(value) else {
        throw CLIExamplesRemindersArgumentError.invalidArguments(
          CLIExamplesRemindersUsage.list
        )
      }
      input.removeFirst()
      invocation.includeCompleted = parsed
      didSetCompleted = true

    case "--flagged":
      invocation.flagged = true
      if !didSetCompleted {
        invocation.includeCompleted = false
      }

    case "--unflagged":
      invocation.flagged = false
      if !didSetCompleted {
        invocation.includeCompleted = false
      }

    case "--scheduled":
      invocation.scheduled = true
      if !didSetCompleted {
        invocation.includeCompleted = false
      }

    case "--today":
      invocation.today = true
      invocation.scheduled = true
      if !didSetCompleted {
        invocation.includeCompleted = false
      }

    case "--priority":
      invocation.priorityRawValue = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.list
      )
      if !didSetCompleted {
        invocation.includeCompleted = false
      }

    default:
      throw CLIExamplesRemindersArgumentError.invalidArguments(
        CLIExamplesRemindersUsage.list
      )
    }
  }

  return invocation
}

private func parseExamplesRemindersSearchOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesRemindersSearchInvocation {
  var terms: [String] = []
  var listID: String?
  var rawTag: String?
  var includeCompleted = false
  var flagged: Bool?
  var scheduled = false
  var today = false
  var priorityRawValue: String?

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--list-id":
      listID = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.search
      )

    case "--tag":
      rawTag = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.search
      )

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
      priorityRawValue = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.search
      )

    default:
      terms.append(option)
    }
  }

  let text = terms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  guard
    !text.isEmpty || rawTag != nil || listID != nil || flagged != nil || scheduled
      || today || priorityRawValue != nil
  else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(
      CLIExamplesRemindersUsage.search
    )
  }

  return CLIExamplesRemindersSearchInvocation(
    text: text,
    listID: listID,
    rawTag: rawTag,
    includeCompleted: includeCompleted,
    flagged: flagged,
    scheduled: scheduled,
    today: today,
    priorityRawValue: priorityRawValue
  )
}

private func parseExamplesReminderAddOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesReminderAddInvocation {
  let listID = try parseRequiredExamplesRemindersArgument(
    from: &input,
    usage: CLIExamplesRemindersUsage.add
  )

  var titleParts: [String] = []
  var notes = ""
  var isFlagged = false
  var dueDateRawValue: String?
  var priorityRawValue: String?

  while let value = input.first {
    input.removeFirst()
    switch value {
    case "--notes":
      guard let rawNotes = input.first else {
        throw CLIExamplesRemindersArgumentError.invalidArguments(
          CLIExamplesRemindersUsage.add
        )
      }
      input.removeFirst()
      notes = rawNotes

    case "--flagged":
      isFlagged = true

    case "--unflagged":
      isFlagged = false

    case "--due-date":
      dueDateRawValue = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.add
      )

    case "--priority":
      priorityRawValue = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.add
      )

    default:
      titleParts.append(value)
    }
  }

  let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  guard !title.isEmpty else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(CLIExamplesRemindersUsage.add)
  }

  return CLIExamplesReminderAddInvocation(
    listID: listID,
    title: title,
    notes: notes,
    isFlagged: isFlagged,
    dueDateRawValue: dueDateRawValue,
    priorityRawValue: priorityRawValue
  )
}

private func parseExamplesReminderUpdateOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesReminderUpdateInvocation {
  let reminderID = try parseRequiredExamplesRemindersArgument(
    from: &input,
    usage: CLIExamplesRemindersUsage.update
  )

  var invocation = CLIExamplesReminderUpdateInvocation(reminderID: reminderID)
  var titleParts: [String] = []
  var didSetField = false

  while let value = input.first {
    input.removeFirst()
    switch value {
    case "--notes":
      guard let rawNotes = input.first else {
        throw CLIExamplesRemindersArgumentError.invalidArguments(
          CLIExamplesRemindersUsage.update
        )
      }
      input.removeFirst()
      invocation.notes = rawNotes
      didSetField = true

    case "--flagged":
      invocation.isFlagged = true
      didSetField = true

    case "--unflagged":
      invocation.isFlagged = false
      didSetField = true

    case "--due-date":
      invocation.dueDateRawValue = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.update
      )
      invocation.clearsDueDate = false
      didSetField = true

    case "--clear-due-date":
      invocation.dueDateRawValue = nil
      invocation.clearsDueDate = true
      didSetField = true

    case "--priority":
      invocation.priorityRawValue = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.update
      )
      invocation.clearsPriority = false
      didSetField = true

    case "--clear-priority":
      invocation.priorityRawValue = nil
      invocation.clearsPriority = true
      didSetField = true

    default:
      titleParts.append(value)
    }
  }

  let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  if !title.isEmpty {
    invocation.title = title
  }
  guard invocation.title != nil || didSetField else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(CLIExamplesRemindersUsage.update)
  }

  return invocation
}

private func parseExamplesRemindersDeleteCompletedOptions(
  from input: inout ArraySlice<String>
) throws -> String? {
  var listID: String?

  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--list-id":
      listID = try parseExamplesRemindersOptionValue(
        from: &input,
        usage: CLIExamplesRemindersUsage.deleteCompleted
      )

    default:
      throw CLIExamplesRemindersArgumentError.invalidArguments(
        CLIExamplesRemindersUsage.deleteCompleted
      )
    }
  }

  return listID
}

private func parseExamplesReminderTagArguments(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> (reminderID: String, rawTag: String) {
  let reminderID = try parseRequiredExamplesRemindersArgument(from: &input, usage: usage)
  let rawTag = joinedTrimmed(input)
  input.removeAll()
  guard !rawTag.isEmpty else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(usage)
  }
  return (reminderID, rawTag)
}

private func parseSingleExamplesRemindersArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredExamplesRemindersArgument(from: &input, usage: usage)
  try requireNoRemainingExamplesRemindersArguments(&input, usage: usage)
  return value
}

private func parseRequiredExamplesRemindersArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(usage)
  }
  return value
}

private func parseExamplesRemindersOptionValue(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIExamplesRemindersArgumentError.invalidArguments(usage)
  }
  return value
}

private func requireNoRemainingExamplesRemindersArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if !input.isEmpty {
    throw CLIExamplesRemindersArgumentError.invalidArguments(usage)
  }
}

private func joinedTrimmed(_ input: ArraySlice<String>) -> String {
  input.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseCLIQueryBool(_ value: String) -> Bool? {
  switch value.lowercased() {
  case "true", "yes", "1":
    return true
  case "false", "no", "0":
    return false
  default:
    return nil
  }
}

private func parseCLIQueryNonNegativeInt(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> Int {
  guard let value = input.first,
    let parsed = Int(value),
    parsed >= 0
  else {
    throw CLIQueryArgumentError.invalidArguments(usage: usage)
  }
  input.removeFirst()
  return parsed
}

private func parseCLIQueryCursor(
  from input: inout ArraySlice<String>,
  option: String,
  inclusive: Bool
) throws -> CLIQueryCursor {
  try parseCLIQueryCursor(
    from: &input,
    option: option,
    inclusive: inclusive,
    usageCommand: CLIQueryUsage.todosCommand
  )
}

private func parseCLIQueryCursor(
  from input: inout ArraySlice<String>,
  option: String,
  inclusive: Bool,
  usageCommand: String
) throws -> CLIQueryCursor {
  guard let value = input.first else {
    throw CLIQueryArgumentError.invalidArguments(
      usage: "Usage: \(usageCommand) \(option) id"
    )
  }
  input.removeFirst()
  let entityID = trimmed(value)
  guard !entityID.isEmpty else {
    throw CLIQueryArgumentError.invalidArguments(
      usage: "Usage: \(usageCommand) \(option) id"
    )
  }
  return CLIQueryCursor(entityID: entityID, inclusive: inclusive)
}

private func parseCLIQuerySortDirection(_ value: String) -> CLIQuerySortDirection? {
  switch value.lowercased() {
  case "asc", "ascending":
    return .ascending
  case "desc", "descending":
    return .descending
  default:
    return nil
  }
}

private func parseCLITodoOrderField(_ value: String) -> CLITodosQueryOrderField? {
  switch value {
  case "none":
    return CLITodosQueryOrderField.none
  case "createdAt":
    return .createdAt
  case "serverCreatedAt":
    return .serverCreatedAt
  default:
    return nil
  }
}

private func parseCLITodoSelectedFields(_ value: String) throws -> [String] {
  let fields =
    value
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  guard !fields.isEmpty else {
    throw CLIQueryArgumentError.invalidArguments(
      usage: "Usage: \(CLIQueryUsage.todosCommand) --select field[,field]"
    )
  }
  return Array(Set(fields)).sorted()
}

private func trimmed(_ string: String) -> String {
  string.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension CLIInitArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownOption(option, usage):
      return "Unknown init option: \(option). \(usage)"
    }
  }
}

extension CLISchemaArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownGenerateOption(option, usage):
      return "Unknown generate option: \(option). \(usage)"

    case let .unknownVerifyOption(option, usage):
      return "Unknown schema verify option: \(option). \(usage)"
    }
  }
}

extension CLIPermissionsArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownGenerateOption(option, usage):
      return "Unknown generate option: \(option). \(usage)"

    case let .unknownVerifyOption(option, usage):
      return "Unknown permissions verify option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesTodosArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownListOption(option, usage):
      return "Unknown todo list option: \(option). Usage: \(usage)"

    case let .unknownWatchOption(option, usage):
      return "Unknown todo watch option: \(option). Usage: \(usage)"
    }
  }
}

extension CLIExamplesAuthArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .invalidEventCount(_, usageCommand):
      return "Usage: \(usageCommand) --events 1"

    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"

    case let .unknownOption(domain, option, usage):
      return "Unknown \(domain) option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesAppBuilderArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"

    case let .unknownOption(option, usage):
      return "Unknown examples app-builder option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesTodoLinksArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage
    }
  }
}

extension CLIExamplesCountersArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage
    }
  }
}

extension CLIExamplesChatArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownPostOption(option, usage):
      return "Unknown chat post option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesMicroblogArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownPostOption(option, usage):
      return "Unknown microblog post option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesMobileChatArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownSendOption(option, usage):
      return "Unknown mobile chat send option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesStroopwafelArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .invalidColor(color, usage):
      return "Invalid Stroopwafel color: \(color). \(usage)"

    case let .invalidScore(score, usage):
      return "Invalid Stroopwafel score: \(score). \(usage)"
    }
  }
}

extension CLIExamplesReactionsArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .invalidReactionName(name, usage):
      return "Invalid reactions name: \(name). \(usage)"

    case let .invalidAngle(angle, usage):
      return "Invalid reactions angle: \(angle). \(usage)"

    case let .unknownTapOption(option, usage):
      return "Unknown reactions tap option: \(option). \(usage)"
    }
  }
}

extension CLIExamplesTypingIndicatorArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage
    }
  }
}

extension CLIExamplesAvatarStackArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage
    }
  }
}

extension CLIExamplesCursorsArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage
    }
  }
}

extension CLIExamplesMergeTileGameArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage
    }
  }
}

extension CLIExamplesSyncUpsArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(message):
      return message

    case .invalidTheme:
      return "Unknown SyncUps theme."
    }
  }
}

extension CLIExamplesRemindersArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(message):
      return message
    }
  }
}

extension CLIQueryArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .invalidArguments(usage):
      return usage

    case let .unknownOption(option, usage):
      return "Unknown todo query option: \(option). Usage: \(usage)"

    case let .conflictingPagination(usage):
      return "Use either --first or --last, not both. Usage: \(usage)"
    }
  }
}

extension CLIValidationArgumentError: CustomStringConvertible {
  public var description: String {
    CLIValidationUsage.validation
  }
}

extension CLIValidationRunnerArgumentError: CustomStringConvertible {
  public var description: String {
    CLIValidationRunnerUsage.validationRunner
  }
}

extension CLIAdminArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIAdminUsage.admin

    case .unknownCommand:
      return CLIAdminUsage.admin

    case let .missingArguments(usage):
      return usage

    case let .invalidNamespace(usage):
      return "\(usage): namespace must not be empty or contain whitespace or '/'."

    case let .invalidEntityID(usage):
      return "\(usage): entity id must not be empty."

    case let .invalidLimit(usage):
      return "\(usage): --limit must be a non-negative integer."

    case let .invalidTransactionID(usage):
      return "\(usage): transaction id must not be empty."

    case let .unknownOption(option, usage):
      if usage == CLIAdminUsage.query {
        return "Unknown admin query option: \(option). \(usage)"
      } else if usage == CLIAdminUsage.transact {
        return "Unknown admin transact option: \(option). \(usage)"
      } else {
        return usage
      }
    }
  }
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

extension CLISyncArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLISyncUsage.sync

    case .unknownCommand:
      return CLISyncUsage.sync

    case let .missingArguments(usage):
      return usage

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLIAppArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIAppUsage.app

    case .unknownCommand:
      return CLIAppUsage.app

    case let .missingArguments(usage):
      return usage

    case let .unknownEphemeralOption(option):
      return "Unknown ephemeral app option: \(option). \(CLIAppUsage.ephemeral)"

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLICacheArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLICacheUsage.cache

    case .unknownCommand:
      return CLICacheUsage.cache

    case let .invalidNamespace(_, usage):
      return "\(usage): namespace must not be empty or contain whitespace or '/'."

    case let .unexpectedArgument(_, usage):
      return usage
    }
  }
}

extension CLIOutboxArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIOutboxUsage.outbox

    case .unknownCommand:
      return CLIOutboxUsage.outbox

    case let .missingArguments(usage):
      return usage

    case let .invalidArguments(usage):
      return usage

    case let .unknownOption(option, usage):
      if usage == CLIOutboxUsage.flush {
        return "Unknown outbox flush option: \(option). \(usage)"
      } else if usage == CLIOutboxUsage.drain {
        return "Unknown outbox drain option: \(option). \(usage)"
      } else {
        return usage
      }

    case let .unexpectedArgument(_, usage):
      return usage
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

    case let .invalidAfterIndex(value, usage):
      return "Invalid --after-index value: \(value). \(usage)"

    case let .invalidOffset(option, value, usage):
      return "Invalid \(option) value: \(value). \(usage)"

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
