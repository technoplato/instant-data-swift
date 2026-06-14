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

public enum CLIExamplesSyncUpsLeafInvocation: Equatable, Sendable {
  case seed
  case list(CLIExamplesSyncUpsListInvocation)
  case detail(syncUpID: String)
  case add(CLIExamplesSyncUpsAddInvocation)
  case update(CLIExamplesSyncUpsUpdateInvocation)
  case addAttendee(syncUpID: String, name: String)
  case record(syncUpID: String, transcript: String)
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
    "Usage: instant-swift-data schema generate --example todos [--to instant.schema.ts] [--json|--jsonl]"
  public static let verify =
    "Usage: instant-swift-data schema verify --example todos --from instant.schema.ts"
}

public enum CLIPermissionsUsage {
  public static let generate =
    "Usage: instant-swift-data perms generate --example todos [--to instant.perms.ts] [--json|--jsonl]"
  public static let verify =
    "Usage: instant-swift-data perms verify --example todos --from instant.perms.ts"
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
}

public enum CLIValidationUsage {
  public static let validation = """
    Usage: instant-swift-data validation <local-todos|local-integrations>
      instant-swift-data validation local-todos [--json|--jsonl]
      instant-swift-data validation local-integrations [--json|--jsonl]
    """
}

public enum CLIValidationArgumentError: Error, Equatable, Sendable {
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
        try parseExamplesTodosQueryOptions(
          from: &input,
          usageCommand: CLIExamplesTodosUsage.listCommand,
          usage: CLIExamplesTodosUsage.list,
          unknown: { option, usage in
            CLIExamplesTodosArgumentError.unknownListOption(option, usage: usage)
          }
        )
      )

    case .watch:
      return .watch(try parseExamplesTodosWatchOptions(from: &input))

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
        try parseExamplesTodosQueryOptions(
          from: &input,
          usageCommand: CLIExamplesTodosUsage.listCommand,
          usage: CLIExamplesTodosUsage.list,
          unknown: { option, usage in
            CLIExamplesTodosArgumentError.unknownListOption(option, usage: usage)
          }
        )
      )

    case let .unknown(command):
      input.removeAll()
      return .unknown(command)
    }
  }
}

public struct CLIExamplesTodoLinksLeafParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodoLinksLeafInvocation {
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

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesRemindersLeafInvocation {
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
        usage: command == "list-tags" ? "Usage: instant-swift-data examples reminders list-tags [--json|--jsonl]" : CLIExamplesRemindersUsage.tags
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

    default:
      throw CLIValidationArgumentError.invalidArguments
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
      let transactionID = try parseRequiredSyncArgument(from: &input, usage: CLISyncUsage.markProcessed)
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
      return .flush(limit: try parseOutboxFlushLimit(from: &input))

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
      return .drain(limit: try parseOutboxDrainLimit(from: &input))

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

private func parseOutboxFlushLimit(
  from input: inout ArraySlice<String>
) throws -> Int? {
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

private func parseOutboxDrainLimit(
  from input: inout ArraySlice<String>
) throws -> Int? {
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

private func parseExamplesTodosQueryOptions(
  from input: inout ArraySlice<String>,
  usageCommand: String,
  usage: String,
  unknown: (String, String) -> any Error
) throws -> CLITodosQueryInvocation {
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

private func parseExamplesTodosWatchOptions(
  from input: inout ArraySlice<String>
) throws -> CLIExamplesTodosWatchInvocation {
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
  guard !text.isEmpty || rawTag != nil || listID != nil || flagged != nil || scheduled
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
  let fields = value
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

extension CLIExamplesTodoLinksArgumentError: CustomStringConvertible {
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
