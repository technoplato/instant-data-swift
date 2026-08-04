import Foundation

/// Seedable parent/child graph for the linked infinite-query recipe.
///
/// Page only the **parent** namespace with `subscribeInfiniteQuery` + `.include`
/// for children. Word-count-style metrics live on the child and are selected
/// from linked snapshots — never a second infinite root on the child namespace.
public struct LinkedInfiniteRecordingRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var updatedAt: InstantTimestamp
  public var transcriptionWordCount: Int

  public init(
    id: String,
    title: String,
    updatedAt: InstantTimestamp,
    transcriptionWordCount: Int = 0
  ) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
    self.transcriptionWordCount = transcriptionWordCount
  }
}

public struct LinkedInfiniteTranscriptionRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var recordingID: String
  public var wordCount: Int
  public var updatedAt: InstantTimestamp

  public init(
    id: String,
    recordingID: String,
    wordCount: Int,
    updatedAt: InstantTimestamp
  ) {
    self.id = id
    self.recordingID = recordingID
    self.wordCount = wordCount
    self.updatedAt = updatedAt
  }
}

public enum LinkedInfiniteExample {
  public static let recordingNamespace = "linked_infinite_recordings"
  public static let transcriptionNamespace = "linked_infinite_transcriptions"
  public static let pageSize = 3

  public static let seedTitles = [
    "Morning standup",
    "Design review",
    "Customer call",
    "Walk notes",
    "Kitchen brainstorm",
    "Evening recap",
    "Agent handoff",
  ]

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: recordingNamespace),
    InstantAttribute(
      id: "\(recordingNamespace)/title",
      namespace: recordingNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(recordingNamespace)/updatedAt",
      namespace: recordingNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    .primaryKey(namespace: transcriptionNamespace),
    InstantAttribute(
      id: "\(transcriptionNamespace)/wordCount",
      namespace: transcriptionNamespace,
      name: "wordCount",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(transcriptionNamespace)/updatedAt",
      namespace: transcriptionNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(transcriptionNamespace)/recording",
      namespace: transcriptionNamespace,
      name: "recording",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "\(transcriptionNamespace)/recording",
      reverseIdentity: "\(recordingNamespace)/transcriptions",
      linkNamespace: recordingNamespace,
      onDelete: .cascade
    ),
  ]

  public static func recordingsQuery(pageSize: Int = pageSize) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.linked-infinite.recordings",
      namespace: recordingNamespace,
      order: InstantQueryOrder("updatedAt", .descending),
      limit: pageSize,
      includes: [
        InstantQueryInclude(
          "transcriptions",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "examples.linked-infinite.included-transcriptions",
            namespace: transcriptionNamespace,
            order: InstantQueryOrder("updatedAt", .descending),
            selectedFields: ["wordCount", "updatedAt", "recording"]
          )
        ),
      ]
    )
  }

  public static func seedLocalIDName(index: Int) -> String {
    "examples.linked-infinite.recording.\(index)"
  }

  public static func transcriptionLocalIDName(index: Int) -> String {
    "examples.linked-infinite.transcription.\(index)"
  }

  public static func createRecordingOperations(
    id: String,
    title: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: recordingNamespace),
      identityOperation(
        id: id,
        namespace: recordingNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(recordingNamespace)/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(recordingNamespace)/updatedAt",
          value: .date(Date(timeIntervalSince1970: Double(updatedAt.milliseconds) / 1_000)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func createTranscriptionOperations(
    id: String,
    recordingID: String,
    wordCount: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: transcriptionNamespace),
      identityOperation(
        id: id,
        namespace: transcriptionNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(transcriptionNamespace)/wordCount",
          value: .number(Double(wordCount)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(transcriptionNamespace)/updatedAt",
          value: .date(Date(timeIntervalSince1970: Double(updatedAt.milliseconds) / 1_000)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(transcriptionNamespace)/recording",
          value: .ref(recordingID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func seedOperations(
    recordingIDs: [String],
    transcriptionIDs: [String],
    baseTime: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    precondition(recordingIDs.count == transcriptionIDs.count)
    precondition(recordingIDs.count == seedTitles.count)
    var operations: [InstantTripleOperation] = []
    for index in recordingIDs.indices {
      let offset = InstantTimestamp(milliseconds: baseTime.milliseconds + Int64(index) * 1_000)
      let wordCount = (index + 1) * 40
      operations += createRecordingOperations(
        id: recordingIDs[index],
        title: seedTitles[index],
        updatedAt: offset,
        transactionID: transactionID
      )
      operations += createTranscriptionOperations(
        id: transcriptionIDs[index],
        recordingID: recordingIDs[index],
        wordCount: wordCount,
        updatedAt: offset,
        transactionID: transactionID
      )
    }
    return operations
  }

  public static func decodeRecordings(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [LinkedInfiniteRecordingRecord] {
    try snapshots.map { snapshot in
      guard case let .string(title) = snapshot.values["title"]?.first else {
        throw decodeError(
          namespace: recordingNamespace,
          id: snapshot.id,
          field: "title",
          expected: "string"
        )
      }
      guard case let .date(updatedAt) = snapshot.values["updatedAt"]?.first else {
        throw decodeError(
          namespace: recordingNamespace,
          id: snapshot.id,
          field: "updatedAt",
          expected: "date"
        )
      }
      let wordCount =
        (snapshot.links?["transcriptions"] ?? [])
        .compactMap { linked -> Int? in
          guard case let .number(value) = linked.values["wordCount"]?.first else { return nil }
          return Int(value)
        }
        .max() ?? 0
      return LinkedInfiniteRecordingRecord(
        id: snapshot.id,
        title: title,
        updatedAt: InstantTimestamp(
          milliseconds: Int64((updatedAt.timeIntervalSince1970 * 1_000).rounded())
        ),
        transcriptionWordCount: wordCount
      )
    }
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func decodeError(
    namespace: String,
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode linked infinite example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for '\(namespace).\(field)'.",
      recovery: "Inspect the linked infinite example triples and attributes."
    )
  }
}
