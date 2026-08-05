import Foundation
import InstantSwiftData

/// Recipe entities mirroring the Scribe join-shaped list pattern:
/// infinite page **recordings**, linked **transcriptions** (wordCount +
/// transcriptText), and per-word rows so soaks exercise the same materialization
/// cost as production Scribe (`#150`).
public struct LinkedInfiniteRecording: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var title: String
  public var updatedAt: Date
  public var startedAtMs: Double?
  public var durationSeconds: Double?

  public static let instantNamespace = "linked_infinite_recordings"
  public static let title = InstantAttributePath<Self, String>("title")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")
  public static let startedAtMs = InstantAttributePath<Self, Double?>("startedAtMs")
  public static let durationSeconds = InstantAttributePath<Self, Double?>("durationSeconds")
  public static let transcriptions = InstantReverseRelation(
    attribute: LinkedInfiniteTranscription.recording
  )

  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "\(instantNamespace)/title",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/updatedAt",
      namespace: instantNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/startedAtMs",
      namespace: instantNamespace,
      name: "startedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/durationSeconds",
      namespace: instantNamespace,
      name: "durationSeconds",
      valueType: .number
    ),
  ]

  public init(
    id: InstantID<Self>,
    title: String,
    updatedAt: Date,
    startedAtMs: Double? = nil,
    durationSeconds: Double? = nil
  ) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
    self.startedAtMs = startedAtMs
    self.durationSeconds = durationSeconds
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first,
      case let .date(updatedAt) = snapshot.values["updatedAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode LinkedInfiniteRecording",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected title and updatedAt.",
        recovery: "Keep the linked-infinite recipe model aligned with its schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.updatedAt = updatedAt
    if case let .number(startedAtMs) = snapshot.values["startedAtMs"]?.first {
      self.startedAtMs = startedAtMs
    } else {
      self.startedAtMs = nil
    }
    if case let .number(durationSeconds) = snapshot.values["durationSeconds"]?.first {
      self.durationSeconds = durationSeconds
    } else {
      self.durationSeconds = nil
    }
  }
}

public struct LinkedInfiniteTranscription: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var recordingID: InstantID<LinkedInfiniteRecording>
  public var wordCount: Double
  public var updatedAt: Date
  public var transcriptText: String?
  public var provider: String?
  public var segmentCount: Double?

  public static let instantNamespace = "linked_infinite_transcriptions"
  public static let recording = InstantAttributePath<Self, InstantID<LinkedInfiniteRecording>>(
    "recording"
  )
  public static let wordCount = InstantAttributePath<Self, Double>("wordCount")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")
  public static let transcriptText = InstantAttributePath<Self, String?>("transcriptText")
  public static let provider = InstantAttributePath<Self, String?>("provider")
  public static let segmentCount = InstantAttributePath<Self, Double?>("segmentCount")

  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "\(instantNamespace)/wordCount",
      namespace: instantNamespace,
      name: "wordCount",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/updatedAt",
      namespace: instantNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/transcriptText",
      namespace: instantNamespace,
      name: "transcriptText",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "\(instantNamespace)/provider",
      namespace: instantNamespace,
      name: "provider",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/segmentCount",
      namespace: instantNamespace,
      name: "segmentCount",
      valueType: .number
    ),
    InstantAttribute(
      id: "\(instantNamespace)/recording",
      namespace: instantNamespace,
      name: "recording",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "\(instantNamespace)/recording",
      reverseIdentity: "linked_infinite_recordings/transcriptions",
      linkNamespace: LinkedInfiniteRecording.instantNamespace,
      onDelete: .cascade
    ),
  ]

  public init(
    id: InstantID<Self>,
    recordingID: InstantID<LinkedInfiniteRecording>,
    wordCount: Double,
    updatedAt: Date,
    transcriptText: String? = nil,
    provider: String? = "Deepgram",
    segmentCount: Double? = 1
  ) {
    self.id = id
    self.recordingID = recordingID
    self.wordCount = wordCount
    self.updatedAt = updatedAt
    self.transcriptText = transcriptText
    self.provider = provider
    self.segmentCount = segmentCount
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
      case let .number(wordCount) = snapshot.values["wordCount"]?.first,
      case let .date(updatedAt) = snapshot.values["updatedAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode LinkedInfiniteTranscription",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected recording, wordCount, and updatedAt.",
        recovery: "Keep the linked-infinite recipe model aligned with its schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.recordingID = InstantID(rawValue: recordingID)
    self.wordCount = wordCount
    self.updatedAt = updatedAt
    if case let .string(transcriptText) = snapshot.values["transcriptText"]?.first {
      self.transcriptText = transcriptText
    } else {
      self.transcriptText = nil
    }
    if case let .string(provider) = snapshot.values["provider"]?.first {
      self.provider = provider
    } else {
      self.provider = nil
    }
    if case let .number(segmentCount) = snapshot.values["segmentCount"]?.first {
      self.segmentCount = segmentCount
    } else {
      self.segmentCount = nil
    }
  }
}

public struct LinkedInfiniteWord: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var recordingID: InstantID<LinkedInfiniteRecording>
  public var transcriptionID: InstantID<LinkedInfiniteTranscription>
  public var text: String
  public var wordIndex: Double
  public var startTimeSeconds: Double
  public var endTimeSeconds: Double
  public var updatedAt: Date

  public static let instantNamespace = "linked_infinite_words"
  public static let recording = InstantAttributePath<Self, InstantID<LinkedInfiniteRecording>>(
    "recording"
  )
  public static let transcription = InstantAttributePath<
    Self, InstantID<LinkedInfiniteTranscription>
  >("transcription")
  public static let text = InstantAttributePath<Self, String>("text")
  public static let wordIndex = InstantAttributePath<Self, Double>("wordIndex")
  public static let startTimeSeconds = InstantAttributePath<Self, Double>("startTimeSeconds")
  public static let endTimeSeconds = InstantAttributePath<Self, Double>("endTimeSeconds")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")

  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "\(instantNamespace)/text",
      namespace: instantNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/wordIndex",
      namespace: instantNamespace,
      name: "wordIndex",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/startTimeSeconds",
      namespace: instantNamespace,
      name: "startTimeSeconds",
      valueType: .number
    ),
    InstantAttribute(
      id: "\(instantNamespace)/endTimeSeconds",
      namespace: instantNamespace,
      name: "endTimeSeconds",
      valueType: .number
    ),
    InstantAttribute(
      id: "\(instantNamespace)/updatedAt",
      namespace: instantNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(instantNamespace)/transcription",
      namespace: instantNamespace,
      name: "transcription",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "\(instantNamespace)/transcription",
      reverseIdentity: "linked_infinite_transcriptions/words",
      linkNamespace: LinkedInfiniteTranscription.instantNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "\(instantNamespace)/recording",
      namespace: instantNamespace,
      name: "recording",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "\(instantNamespace)/recording",
      reverseIdentity: "linked_infinite_recordings/words",
      linkNamespace: LinkedInfiniteRecording.instantNamespace,
      onDelete: .cascade
    ),
  ]

  public init(
    id: InstantID<Self>,
    recordingID: InstantID<LinkedInfiniteRecording>,
    transcriptionID: InstantID<LinkedInfiniteTranscription>,
    text: String,
    wordIndex: Double,
    startTimeSeconds: Double,
    endTimeSeconds: Double,
    updatedAt: Date
  ) {
    self.id = id
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.text = text
    self.wordIndex = wordIndex
    self.startTimeSeconds = startTimeSeconds
    self.endTimeSeconds = endTimeSeconds
    self.updatedAt = updatedAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
      case let .ref(transcriptionID) = snapshot.values["transcription"]?.first,
      case let .string(text) = snapshot.values["text"]?.first,
      case let .number(wordIndex) = snapshot.values["wordIndex"]?.first,
      case let .number(startTimeSeconds) = snapshot.values["startTimeSeconds"]?.first,
      case let .number(endTimeSeconds) = snapshot.values["endTimeSeconds"]?.first,
      case let .date(updatedAt) = snapshot.values["updatedAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode LinkedInfiniteWord",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected recording, transcription, text, timings, and updatedAt.",
        recovery: "Keep the linked-infinite recipe model aligned with its schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.recordingID = InstantID(rawValue: recordingID)
    self.transcriptionID = InstantID(rawValue: transcriptionID)
    self.text = text
    self.wordIndex = wordIndex
    self.startTimeSeconds = startTimeSeconds
    self.endTimeSeconds = endTimeSeconds
    self.updatedAt = updatedAt
  }
}

/// List row: wordCount selected from included transcriptions (single source of truth).
public struct LinkedInfiniteListRow: Hashable, Identifiable, Sendable {
  public var id: InstantID<LinkedInfiniteRecording>
  public var title: String
  public var updatedAt: Date
  public var wordCount: Int

  public init(
    id: InstantID<LinkedInfiniteRecording>,
    title: String,
    updatedAt: Date,
    wordCount: Int
  ) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
    self.wordCount = wordCount
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    let recording = try LinkedInfiniteRecording(snapshot: snapshot)
    let wordCount =
      (snapshot.links?["transcriptions"] ?? [])
      .compactMap { linked -> Int? in
        guard case let .number(value) = linked.values["wordCount"]?.first else { return nil }
        return Int(value)
      }
      .max() ?? 0
    self.init(
      id: recording.id,
      title: recording.title,
      updatedAt: recording.updatedAt,
      wordCount: wordCount
    )
  }

  /// One infinite root + include. Nested pagination on the include is forbidden.
  /// Default page size matches Scribe's library list (50), not the old demo size 3.
  public static func pageQuery(pageSize: Int = 50) -> InstantEntityQuery<LinkedInfiniteRecording> {
    LinkedInfiniteRecording.query
      .order(LinkedInfiniteRecording.updatedAt, .descending)
      .limit(UInt(pageSize))
      .include(
        LinkedInfiniteRecording.transcriptions,
        LinkedInfiniteTranscription.query
          .order(LinkedInfiniteTranscription.updatedAt, .descending)
          .select(
            LinkedInfiniteTranscription.wordCount,
            LinkedInfiniteTranscription.updatedAt,
            LinkedInfiniteTranscription.transcriptText,
            LinkedInfiniteTranscription.provider,
            LinkedInfiniteTranscription.segmentCount
          )
      )
  }
}

public enum LinkedInfiniteSeed {
  /// Demo titles (short soak). Prefer `scribeShapedSeed` for production-like volume.
  public static let titles = [
    "Morning standup",
    "Design review",
    "Customer call",
    "Walk notes",
    "Kitchen brainstorm",
    "Evening recap",
    "Agent handoff",
    "Sprint planning",
    "Bug triage",
    "Demo dry-run",
    "Pair programming",
    "Release checklist",
    "User interview",
    "Architecture notes",
    "On-call handoff",
    "Metrics review",
    "Retro action items",
    "Docs cleanup",
    "Infra drift",
    "Feature flags audit",
  ]

  /// Matches library publish-gate profile (#150) so the recipe cannot hide multi-GB growth.
  public static let scribeShapedRecordingCount = 80
  public static let scribeShapedWordsPerRecording = 40
  public static let scribeShapedTranscriptCharacters = 1_024

  public static var instantAttributes: [InstantAttribute] {
    LinkedInfiniteRecording.instantAttributes
      + LinkedInfiniteTranscription.instantAttributes
      + LinkedInfiniteWord.instantAttributes
  }

  @discardableResult
  public static func seed(
    using client: InstantSwiftDataClient,
    now: Date = Date(),
    makeID: () -> String = { UUID().uuidString.lowercased() },
    scribeShaped: Bool = true
  ) async throws -> [LinkedInfiniteListRow] {
    if scribeShaped {
      return try await scribeShapedSeed(using: client, now: now, makeID: makeID)
    }
    return try await demoSeed(using: client, now: now, makeID: makeID)
  }

  @discardableResult
  public static func demoSeed(
    using client: InstantSwiftDataClient,
    now: Date = Date(),
    makeID: () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> [LinkedInfiniteListRow] {
    var plannedRows: [LinkedInfiniteListRow] = []
    var mutations: [InstantMutation] = []
    for (index, title) in titles.enumerated() {
      let recordingID = InstantID<LinkedInfiniteRecording>(rawValue: makeID())
      let transcriptionID = InstantID<LinkedInfiniteTranscription>(rawValue: makeID())
      let updatedAt = now.addingTimeInterval(TimeInterval(index))
      let wordCount = Double((index + 1) * 40)
      mutations.append(
        LinkedInfiniteRecording.create(
          id: recordingID,
          LinkedInfiniteRecording.title.set(title),
          LinkedInfiniteRecording.updatedAt.set(updatedAt),
          LinkedInfiniteRecording.startedAtMs.set(updatedAt.timeIntervalSince1970 * 1_000),
          LinkedInfiniteRecording.durationSeconds.set(Double(30 + index))
        )
      )
      mutations.append(
        LinkedInfiniteTranscription.create(
          id: transcriptionID,
          LinkedInfiniteTranscription.recording.set(recordingID),
          LinkedInfiniteTranscription.wordCount.set(wordCount),
          LinkedInfiniteTranscription.updatedAt.set(updatedAt),
          LinkedInfiniteTranscription.provider.set("Deepgram"),
          LinkedInfiniteTranscription.segmentCount.set(1),
          LinkedInfiniteTranscription.transcriptText.set(
            String(repeating: "demo word ", count: 20)
          )
        )
      )
      plannedRows.append(
        LinkedInfiniteListRow(
          id: recordingID,
          title: title,
          updatedAt: updatedAt,
          wordCount: Int(wordCount)
        )
      )
    }
    let seededMutations = mutations
    try await client.transact {
      for mutation in seededMutations {
        mutation
      }
    }
    return plannedRows.sorted { $0.updatedAt > $1.updatedAt }
  }

  /// Production-shaped seed: many recordings + transcript text + word entities.
  @discardableResult
  public static func scribeShapedSeed(
    using client: InstantSwiftDataClient,
    now: Date = Date(),
    makeID: () -> String = { UUID().uuidString.lowercased() },
    recordingCount: Int = scribeShapedRecordingCount,
    wordsPerRecording: Int = scribeShapedWordsPerRecording,
    transcriptCharacters: Int = scribeShapedTranscriptCharacters
  ) async throws -> [LinkedInfiniteListRow] {
    var plannedRows: [LinkedInfiniteListRow] = []
    var mutations: [InstantMutation] = []
    let transcriptText = String(
      repeating: "testing ",
      count: max(1, transcriptCharacters / 8)
    )
    for index in 0..<recordingCount {
      let recordingID = InstantID<LinkedInfiniteRecording>(rawValue: makeID())
      let transcriptionID = InstantID<LinkedInfiniteTranscription>(rawValue: makeID())
      let updatedAt = now.addingTimeInterval(TimeInterval(index))
      let title = "Recording \(String(format: "%03d", index + 1)) — soak"
      let wordCount = Double(wordsPerRecording)
      mutations.append(
        LinkedInfiniteRecording.create(
          id: recordingID,
          LinkedInfiniteRecording.title.set(title),
          LinkedInfiniteRecording.updatedAt.set(updatedAt),
          LinkedInfiniteRecording.startedAtMs.set(updatedAt.timeIntervalSince1970 * 1_000),
          LinkedInfiniteRecording.durationSeconds.set(Double(30 + (index % 120)))
        )
      )
      mutations.append(
        LinkedInfiniteTranscription.create(
          id: transcriptionID,
          LinkedInfiniteTranscription.recording.set(recordingID),
          LinkedInfiniteTranscription.wordCount.set(wordCount),
          LinkedInfiniteTranscription.updatedAt.set(updatedAt),
          LinkedInfiniteTranscription.provider.set("Deepgram"),
          LinkedInfiniteTranscription.segmentCount.set(Double(max(1, wordsPerRecording / 40))),
          LinkedInfiniteTranscription.transcriptText.set(transcriptText)
        )
      )
      for wordIndex in 0..<wordsPerRecording {
        let wordID = InstantID<LinkedInfiniteWord>(rawValue: makeID())
        let start = Double(wordIndex) * 0.25
        mutations.append(
          LinkedInfiniteWord.create(
            id: wordID,
            LinkedInfiniteWord.recording.set(recordingID),
            LinkedInfiniteWord.transcription.set(transcriptionID),
            LinkedInfiniteWord.text.set("w\(wordIndex)"),
            LinkedInfiniteWord.wordIndex.set(Double(wordIndex)),
            LinkedInfiniteWord.startTimeSeconds.set(start),
            LinkedInfiniteWord.endTimeSeconds.set(start + 0.2),
            LinkedInfiniteWord.updatedAt.set(updatedAt)
          )
        )
      }
      plannedRows.append(
        LinkedInfiniteListRow(
          id: recordingID,
          title: title,
          updatedAt: updatedAt,
          wordCount: wordsPerRecording
        )
      )
    }
    let seededMutations = mutations
    try await client.transact {
      for mutation in seededMutations {
        mutation
      }
    }
    return plannedRows.sorted { $0.updatedAt > $1.updatedAt }
  }
}
