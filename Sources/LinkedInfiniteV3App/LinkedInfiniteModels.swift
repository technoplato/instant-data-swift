import Foundation
import InstantSwiftData

/// Recipe entities mirroring the Scribe join-shaped list pattern:
/// infinite page **recordings**, linked **transcriptions** for wordCount.
public struct LinkedInfiniteRecording: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var title: String
  public var updatedAt: Date

  public static let instantNamespace = "linked_infinite_recordings"
  public static let title = InstantAttributePath<Self, String>("title")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")
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
  ]

  public init(id: InstantID<Self>, title: String, updatedAt: Date) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
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
  }
}

public struct LinkedInfiniteTranscription: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var recordingID: InstantID<LinkedInfiniteRecording>
  public var wordCount: Double
  public var updatedAt: Date

  public static let instantNamespace = "linked_infinite_transcriptions"
  public static let recording = InstantAttributePath<Self, InstantID<LinkedInfiniteRecording>>(
    "recording"
  )
  public static let wordCount = InstantAttributePath<Self, Double>("wordCount")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")

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
    updatedAt: Date
  ) {
    self.id = id
    self.recordingID = recordingID
    self.wordCount = wordCount
    self.updatedAt = updatedAt
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
  public static func pageQuery(pageSize: Int = 3) -> InstantEntityQuery<LinkedInfiniteRecording> {
    LinkedInfiniteRecording.query
      .order(LinkedInfiniteRecording.updatedAt, .descending)
      .limit(UInt(pageSize))
      .include(
        LinkedInfiniteRecording.transcriptions,
        LinkedInfiniteTranscription.query
          .order(LinkedInfiniteTranscription.updatedAt, .descending)
          .select(
            LinkedInfiniteTranscription.wordCount,
            LinkedInfiniteTranscription.updatedAt
          )
      )
  }
}

public enum LinkedInfiniteSeed {
  public static let titles = [
    "Morning standup",
    "Design review",
    "Customer call",
    "Walk notes",
    "Kitchen brainstorm",
    "Evening recap",
    "Agent handoff",
  ]

  public static var instantAttributes: [InstantAttribute] {
    LinkedInfiniteRecording.instantAttributes + LinkedInfiniteTranscription.instantAttributes
  }

  @discardableResult
  public static func seed(
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
          LinkedInfiniteRecording.updatedAt.set(updatedAt)
        )
      )
      mutations.append(
        LinkedInfiniteTranscription.create(
          id: transcriptionID,
          LinkedInfiniteTranscription.recording.set(recordingID),
          LinkedInfiniteTranscription.wordCount.set(wordCount),
          LinkedInfiniteTranscription.updatedAt.set(updatedAt)
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
}
