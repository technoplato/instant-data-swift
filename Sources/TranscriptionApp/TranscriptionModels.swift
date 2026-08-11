import Foundation
import InstantSwiftData

// MARK: - Instant entities (ADR 0016)
//
// Style: `@InstantEntity` + stored properties only. The macro owns namespace,
// attribute paths, and `instantAttributes`. Do not hand-write attribute tables.
//
// `init(snapshot:)` is required by `InstantEntityModel` today (library gap —
// not synthesized). Decode with typed `snapshot.value(Self.field)` paths.

/// Capture identity (list row).
@InstantEntity
public struct Recording: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Recording>
  public var title: String
  public var createdAt: Date
  public var updatedAt: Date
  public var finishedAt: Date?
  public var durationMilliseconds: Int

  public init(
    id: InstantID<Recording> = InstantID(),
    title: String,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    finishedAt: Date? = nil,
    durationMilliseconds: Int = 0
  ) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.finishedAt = finishedAt
    self.durationMilliseconds = durationMilliseconds
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.value(Self.title)
    createdAt = try snapshot.value(Self.createdAt)
    updatedAt = try snapshot.value(Self.updatedAt)
    finishedAt = try snapshot.value(Self.finishedAt)
    durationMilliseconds = try snapshot.value(Self.durationMilliseconds)
  }

  public static var list: InstantQuery<Self> {
    query.order(createdAt, .descending)
  }
}

/// One ordered segment list owned by a recording.
@InstantEntity
public struct Transcription: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Transcription>
  @InstantRelation(reverse: "transcriptions")
  public var recording: InstantID<Recording>
  public var createdAt: Date
  public var updatedAt: Date
  public var finishedAt: Date?

  public init(
    id: InstantID<Transcription> = InstantID(),
    recording: InstantID<Recording>,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    finishedAt: Date? = nil
  ) {
    self.id = id
    self.recording = recording
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.finishedAt = finishedAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    recording = try snapshot.value(Self.recording)
    createdAt = try snapshot.value(Self.createdAt)
    updatedAt = try snapshot.value(Self.updatedAt)
    finishedAt = try snapshot.value(Self.finishedAt)
  }

  public static func forRecording(_ id: InstantID<Recording>) -> InstantQuery<Self> {
    query.where(recording == id).order(createdAt, .descending)
  }
}

/// Timeline row. Speech body: words JSON + derived text (v1 teachable).
@InstantEntity
public struct Segment: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Segment>
  @InstantRelation(reverse: "segments")
  public var transcription: InstantID<Transcription>
  public var index: Int
  public var wallStart: Date
  public var wallEnd: Date
  public var relativeStartMilliseconds: Int
  public var relativeEndMilliseconds: Int
  /// `speech` or `event`.
  public var bodyKind: String
  public var wordsJSON: String
  public var text: String
  public var isFinal: Bool

  public init(
    id: InstantID<Segment> = InstantID(),
    transcription: InstantID<Transcription>,
    index: Int,
    wallStart: Date = .now,
    wallEnd: Date = .now,
    relativeStartMilliseconds: Int = 0,
    relativeEndMilliseconds: Int = 0,
    bodyKind: String = "speech",
    wordsJSON: String = "[]",
    text: String = "",
    isFinal: Bool = false
  ) {
    self.id = id
    self.transcription = transcription
    self.index = index
    self.wallStart = wallStart
    self.wallEnd = wallEnd
    self.relativeStartMilliseconds = relativeStartMilliseconds
    self.relativeEndMilliseconds = relativeEndMilliseconds
    self.bodyKind = bodyKind
    self.wordsJSON = wordsJSON
    self.text = text
    self.isFinal = isFinal
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    transcription = try snapshot.value(Self.transcription)
    index = try snapshot.value(Self.index)
    wallStart = try snapshot.value(Self.wallStart)
    wallEnd = try snapshot.value(Self.wallEnd)
    relativeStartMilliseconds = try snapshot.value(Self.relativeStartMilliseconds)
    relativeEndMilliseconds = try snapshot.value(Self.relativeEndMilliseconds)
    bodyKind = try snapshot.value(Self.bodyKind)
    wordsJSON = try snapshot.value(Self.wordsJSON)
    text = try snapshot.value(Self.text)
    isFinal = try snapshot.value(Self.isFinal)
  }

  public static func forTranscription(_ id: InstantID<Transcription>) -> InstantQuery<Self> {
    query.where(transcription == id).order(index)
  }

  public var words: [String] {
    guard let data = wordsJSON.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return decoded
  }

  public static func encodeWords(_ words: [String]) -> String {
    guard let data = try? JSONEncoder().encode(words),
      let string = String(data: data, encoding: .utf8)
    else { return "[]" }
    return string
  }
}

/// Host preferences (schema). Not an app-tree root. Singleton row.
@InstantEntity
public struct Preference: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Preference>
  public var speechRate: Double
  public var speechRateDefault: Double
  /// expanded | collapsed | hidden
  public var debugPanelPresentation: String

  public static let singletonID = InstantID<Preference>(rawValue: "preference-singleton")

  public init(
    id: InstantID<Preference> = singletonID,
    speechRate: Double = 1.0,
    speechRateDefault: Double = 1.0,
    debugPanelPresentation: String = "expanded"
  ) {
    self.id = id
    self.speechRate = speechRate
    self.speechRateDefault = speechRateDefault
    self.debugPanelPresentation = debugPanelPresentation
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    speechRate = try snapshot.value(Self.speechRate)
    speechRateDefault = try snapshot.value(Self.speechRateDefault)
    debugPanelPresentation = try snapshot.value(Self.debugPanelPresentation)
  }
}
