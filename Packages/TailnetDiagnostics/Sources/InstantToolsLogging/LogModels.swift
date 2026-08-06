import Foundation

/// The severity of a portable structured log event.
public enum LogLevel: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case debug
  case info
  case notice
  case warning
  case error
  case critical
}

/// The source-code location that emitted a structured log event.
public struct LogSourceLocation: Codable, Equatable, Hashable, Sendable {
  public var fileID: String
  public var function: String
  public var line: Int

  public init(
    fileID: String,
    function: String,
    line: Int
  ) {
    self.fileID = fileID
    self.function = function
    self.line = line
  }
}

/// A canonical, viewer-ready reference from one log event to one tracked issue.
public struct IssueLogReference: Codable, Equatable, Hashable, Sendable {
  public var issueID: String
  public var viewerURL: String

  public init(
    issueID: String,
    viewerBaseURL: String = "https://issues.knophy.com"
  ) {
    self.issueID = Self.normalize(issueID)
    self.viewerURL = "\(viewerBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/issues/\(self.issueID)"
  }

  private static func normalize(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidate = trimmed
    let lowercase = candidate.lowercased()

    if lowercase.hasPrefix("issue") {
      candidate = String(candidate.dropFirst("issue".count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if candidate.first == "#" || candidate.first == "-" {
        candidate.removeFirst()
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    } else if candidate.first == "#" {
      candidate.removeFirst()
      candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard
      !candidate.isEmpty,
      candidate.allSatisfy({ $0.isASCII && $0.isNumber }),
      let number = Int(candidate),
      number > 0
    else { return trimmed }
    return number < 1_000 ? String(format: "%03d", number) : String(number)
  }
}

/// How a source path currently relates to an issue under investigation.
public enum LogPathRelationship: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case suspected
  case contributing
  case ruledOut
}

/// A source path and the current strength of evidence connecting it to an issue.
public struct LogContributingPath: Codable, Equatable, Hashable, Sendable {
  public var path: String
  public var reason: String?
  public var relationship: LogPathRelationship

  public init(
    path: String,
    reason: String? = nil,
    relationship: LogPathRelationship
  ) {
    self.path = path
    self.reason = reason
    self.relationship = relationship
  }

  public static func suspected(_ path: String, reason: String? = nil) -> Self {
    Self(path: path, reason: reason, relationship: .suspected)
  }

  public static func contributing(_ path: String, reason: String? = nil) -> Self {
    Self(path: path, reason: reason, relationship: .contributing)
  }

  public static func ruledOut(_ path: String, reason: String? = nil) -> Self {
    Self(path: path, reason: reason, relationship: .ruledOut)
  }
}

/// One transport-independent structured log event.
public struct LogEvent: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var category: String
  public var contributingPaths: [LogContributingPath]
  public var directQuote: String?
  public var id: String
  public var issueReferences: [IssueLogReference]
  public var level: LogLevel
  public var message: String
  public var metadata: [String: String]
  public var name: String
  public var source: LogSourceLocation
  public var timestamp: Date

  public init(
    category: String,
    contributingPaths: [LogContributingPath] = [],
    directQuote: String? = nil,
    id: String,
    issueReferences: [IssueLogReference] = [],
    level: LogLevel = .info,
    message: String,
    metadata: [String: String] = [:],
    name: String,
    timestamp: Date,
    fileID: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    self.category = category
    self.contributingPaths = contributingPaths
    self.directQuote = directQuote
    self.id = id
    self.issueReferences = Self.mergedIssueReferences(
      explicit: issueReferences,
      message: message,
      directQuote: directQuote,
      metadata: metadata
    )
    self.level = level
    self.message = message
    self.metadata = metadata
    self.name = name
    self.source = LogSourceLocation(
      fileID: String(describing: fileID),
      function: String(describing: function),
      line: Int(line)
    )
    self.timestamp = timestamp
  }

  private enum CodingKeys: String, CodingKey {
    case category
    case contributingPaths
    case directQuote
    case id
    case issueReferences
    case level
    case message
    case metadata
    case name
    case source
    case timestamp
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    category = try container.decode(String.self, forKey: .category)
    contributingPaths =
      try container.decodeIfPresent([LogContributingPath].self, forKey: .contributingPaths) ?? []
    directQuote = try container.decodeIfPresent(String.self, forKey: .directQuote)
    id = try container.decode(String.self, forKey: .id)
    level = try container.decode(LogLevel.self, forKey: .level)
    message = try container.decode(String.self, forKey: .message)
    metadata = try container.decode([String: String].self, forKey: .metadata)
    name = try container.decode(String.self, forKey: .name)
    source = try container.decode(LogSourceLocation.self, forKey: .source)
    timestamp = try container.decode(Date.self, forKey: .timestamp)
    issueReferences = Self.mergedIssueReferences(
      explicit:
        try container.decodeIfPresent([IssueLogReference].self, forKey: .issueReferences) ?? [],
      message: message,
      directQuote: directQuote,
      metadata: metadata
    )
  }

  private static func mergedIssueReferences(
    explicit: [IssueLogReference],
    message: String,
    directQuote: String?,
    metadata: [String: String]
  ) -> [IssueLogReference] {
    var issueIDs = Set(explicit.map(\.issueID))
    let searchable = [message, directQuote]
      .compactMap { $0 }
      + metadata.compactMap { key, value in
        key.lowercased().contains("issue") ? value : nil
      }

    let pattern = #"(?i)(?:\bissue\s*(?:#|-)?\s*|#)([0-9]{1,6})\b"#
    let expression = try? NSRegularExpression(pattern: pattern)
    for value in searchable {
      let range = NSRange(value.startIndex..., in: value)
      expression?.enumerateMatches(in: value, range: range) { match, _, _ in
        guard
          let match,
          let capture = Range(match.range(at: 1), in: value)
        else { return }
        issueIDs.insert(IssueLogReference(issueID: String(value[capture])).issueID)
      }
      if let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
        issueIDs.insert(IssueLogReference(issueID: String(number)).issueID)
      }
    }

    let explicitByID = Dictionary(uniqueKeysWithValues: explicit.map { ($0.issueID, $0) })
    return issueIDs.sorted().map { explicitByID[$0] ?? IssueLogReference(issueID: $0) }
  }
}

/// A portable filter for structured log-store queries.
public struct LogQuery: Codable, Equatable, Hashable, Sendable {
  public var categories: Set<String>
  public var levels: Set<LogLevel>
  public var limit: Int
  public var names: Set<String>

  public init(
    categories: Set<String> = [],
    levels: Set<LogLevel> = [],
    limit: Int = 100,
    names: Set<String> = []
  ) {
    self.categories = categories
    self.levels = levels
    self.limit = limit
    self.names = names
  }
}
