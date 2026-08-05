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

/// Production-shaped volume for the linked-infinite memory soak.
///
/// Sampled from Scribe main Instant via admin query on 2026-08-05
/// (`SCRIBE_MAIN_INSTANT_APP_ID`): ≥239 recordings, ≥214 transcriptions,
/// ≥2000 words, ≥2000 segments, ≥246 attachments. The soak is intentionally
/// a lower bound that still forces word-entity materialization (the recipe's
/// old seed only stored a `wordCount` number).
public struct LinkedInfiniteScribeShapedSoakProfile: Hashable, Sendable {
  public var recordingCount: Int
  public var wordsPerRecording: Int
  public var transcriptTextCharacters: Int
  public var listPageSize: Int
  /// Physical footprint growth budget for seed + infinite page through soak.
  public var footprintGrowthBudgetBytes: UInt64
  /// Absolute physical footprint ceiling after soak (Debug suite overhead).
  public var footprintCeilingBytes: UInt64

  public init(
    recordingCount: Int,
    wordsPerRecording: Int,
    transcriptTextCharacters: Int,
    listPageSize: Int,
    footprintGrowthBudgetBytes: UInt64,
    footprintCeilingBytes: UInt64
  ) {
    self.recordingCount = recordingCount
    self.wordsPerRecording = wordsPerRecording
    self.transcriptTextCharacters = transcriptTextCharacters
    self.listPageSize = listPageSize
    self.footprintGrowthBudgetBytes = footprintGrowthBudgetBytes
    self.footprintCeilingBytes = footprintCeilingBytes
  }

  /// Default CI soak: ~80 parents × 120 words ≈ 9.6k word entities + transcript text.
  /// Page size 50 matches Scribe's library infinite list (not the recipe's demo page size 3).
  ///
  /// Measured Debug suite cost on 2026-08-05 (this machine): seed ~450 MiB
  /// footprint from a cold baseline; infinite page expands added &lt;1 MiB.
  /// Budgets catch multi‑GB thrash (the historical Jetsam class) without
  /// failing the expected seed cost. Gate on **footprint**, never VSZ.
  public static let publishGate = LinkedInfiniteScribeShapedSoakProfile(
    recordingCount: 80,
    wordsPerRecording: 120,
    transcriptTextCharacters: 2_048,
    listPageSize: 50,
    footprintGrowthBudgetBytes: 768 * 1_024 * 1_024,
    footprintCeilingBytes: 1_024 * 1_024 * 1_024
  )

  public var estimatedWordEntities: Int { recordingCount * wordsPerRecording }
}

public enum LinkedInfiniteExample {
  public static let recordingNamespace = "linked_infinite_recordings"
  public static let transcriptionNamespace = "linked_infinite_transcriptions"
  public static let wordNamespace = "linked_infinite_words"
  public static let pageSize = 3
  /// Scribe library list default page size (production infinite root).
  public static let scribeListPageSize = 50

  public static let seedTitles = [
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
    InstantAttribute(
      id: "\(recordingNamespace)/startedAtMs",
      namespace: recordingNamespace,
      name: "startedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(recordingNamespace)/durationSeconds",
      namespace: recordingNamespace,
      name: "durationSeconds",
      valueType: .number
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
      id: "\(transcriptionNamespace)/transcriptText",
      namespace: transcriptionNamespace,
      name: "transcriptText",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "\(transcriptionNamespace)/provider",
      namespace: transcriptionNamespace,
      name: "provider",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(transcriptionNamespace)/segmentCount",
      namespace: transcriptionNamespace,
      name: "segmentCount",
      valueType: .number
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
    .primaryKey(namespace: wordNamespace),
    InstantAttribute(
      id: "\(wordNamespace)/text",
      namespace: wordNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(wordNamespace)/wordIndex",
      namespace: wordNamespace,
      name: "wordIndex",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(wordNamespace)/startTimeSeconds",
      namespace: wordNamespace,
      name: "startTimeSeconds",
      valueType: .number
    ),
    InstantAttribute(
      id: "\(wordNamespace)/endTimeSeconds",
      namespace: wordNamespace,
      name: "endTimeSeconds",
      valueType: .number
    ),
    InstantAttribute(
      id: "\(wordNamespace)/updatedAt",
      namespace: wordNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(wordNamespace)/transcription",
      namespace: wordNamespace,
      name: "transcription",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "\(wordNamespace)/transcription",
      reverseIdentity: "\(transcriptionNamespace)/words",
      linkNamespace: transcriptionNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "\(wordNamespace)/recording",
      namespace: wordNamespace,
      name: "recording",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "\(wordNamespace)/recording",
      reverseIdentity: "\(recordingNamespace)/words",
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
            selectedFields: [
              "wordCount",
              "updatedAt",
              "recording",
              "transcriptText",
              "provider",
              "segmentCount",
            ]
          )
        ),
      ]
    )
  }

  /// Scribe library list shape: page 50 parents + transcription metrics include.
  public static func scribeShapedListQuery(
    pageSize: Int = scribeListPageSize
  ) -> InstantQueryPlan {
    recordingsQuery(pageSize: pageSize)
  }

  public static func seedLocalIDName(index: Int) -> String {
    "examples.linked-infinite.recording.\(index)"
  }

  public static func transcriptionLocalIDName(index: Int) -> String {
    "examples.linked-infinite.transcription.\(index)"
  }

  public static func wordLocalIDName(recordingIndex: Int, wordIndex: Int) -> String {
    "examples.linked-infinite.word.\(recordingIndex).\(wordIndex)"
  }

  public static func createRecordingOperations(
    id: String,
    title: String,
    updatedAt: InstantTimestamp,
    transactionID: String,
    startedAtMs: Double? = nil,
    durationSeconds: Double? = nil
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = [
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
    if let startedAtMs {
      operations.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(recordingNamespace)/startedAtMs",
            value: .number(startedAtMs),
            txID: transactionID,
            txTime: updatedAt
          )
        )
      )
    }
    if let durationSeconds {
      operations.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(recordingNamespace)/durationSeconds",
            value: .number(durationSeconds),
            txID: transactionID,
            txTime: updatedAt
          )
        )
      )
    }
    return operations
  }

  public static func createTranscriptionOperations(
    id: String,
    recordingID: String,
    wordCount: Int,
    updatedAt: InstantTimestamp,
    transactionID: String,
    transcriptText: String? = nil,
    provider: String = "Deepgram",
    segmentCount: Int = 1
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = [
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
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(transcriptionNamespace)/provider",
          value: .string(provider),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(transcriptionNamespace)/segmentCount",
          value: .number(Double(segmentCount)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
    if let transcriptText {
      operations.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(transcriptionNamespace)/transcriptText",
            value: .string(transcriptText),
            txID: transactionID,
            txTime: updatedAt
          )
        )
      )
    }
    return operations
  }

  public static func createWordOperations(
    id: String,
    recordingID: String,
    transcriptionID: String,
    text: String,
    wordIndex: Int,
    startTimeSeconds: Double,
    endTimeSeconds: Double,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: wordNamespace),
      identityOperation(
        id: id,
        namespace: wordNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/text",
          value: .string(text),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/wordIndex",
          value: .number(Double(wordIndex)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/startTimeSeconds",
          value: .number(startTimeSeconds),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/endTimeSeconds",
          value: .number(endTimeSeconds),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/updatedAt",
          value: .date(Date(timeIntervalSince1970: Double(updatedAt.milliseconds) / 1_000)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/transcription",
          value: .ref(transcriptionID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/recording",
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

  /// Scribe-shaped soak seed: many parents, transcript text, and per-word entities.
  public static func scribeShapedSoakOperations(
    profile: LinkedInfiniteScribeShapedSoakProfile = .publishGate,
    recordingIDs: [String],
    transcriptionIDs: [String],
    wordIDsByRecording: [[String]],
    baseTime: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    precondition(recordingIDs.count == profile.recordingCount)
    precondition(transcriptionIDs.count == profile.recordingCount)
    precondition(wordIDsByRecording.count == profile.recordingCount)
    let fillerWord = "testing "
    let transcriptText = String(
      repeating: fillerWord,
      count: max(1, profile.transcriptTextCharacters / fillerWord.count)
    )
    var operations: [InstantTripleOperation] = []
    for index in recordingIDs.indices {
      let offset = InstantTimestamp(milliseconds: baseTime.milliseconds + Int64(index) * 1_000)
      let title = "Recording \(String(format: "%03d", index + 1)) — soak"
      let wordIDs = wordIDsByRecording[index]
      precondition(wordIDs.count == profile.wordsPerRecording)
      operations += createRecordingOperations(
        id: recordingIDs[index],
        title: title,
        updatedAt: offset,
        transactionID: transactionID,
        startedAtMs: Double(offset.milliseconds),
        durationSeconds: Double(30 + index)
      )
      operations += createTranscriptionOperations(
        id: transcriptionIDs[index],
        recordingID: recordingIDs[index],
        wordCount: profile.wordsPerRecording,
        updatedAt: offset,
        transactionID: transactionID,
        transcriptText: transcriptText,
        provider: "Deepgram",
        segmentCount: max(1, profile.wordsPerRecording / 40)
      )
      for (wordIndex, wordID) in wordIDs.enumerated() {
        let start = Double(wordIndex) * 0.25
        operations += createWordOperations(
          id: wordID,
          recordingID: recordingIDs[index],
          transcriptionID: transcriptionIDs[index],
          text: "w\(wordIndex)",
          wordIndex: wordIndex,
          startTimeSeconds: start,
          endTimeSeconds: start + 0.2,
          updatedAt: offset,
          transactionID: transactionID
        )
      }
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

  /// Server attribute blobs used by live-refresh fixtures (IDs match join-row columns).
  public static var serverAttrs: [InstantLiveJSONValue] {
    [
      serverAttr(id: "\(recordingNamespace)/id", namespace: recordingNamespace, name: "id"),
      serverAttr(id: "\(recordingNamespace)/title", namespace: recordingNamespace, name: "title"),
      serverAttr(
        id: "\(recordingNamespace)/updatedAt",
        namespace: recordingNamespace,
        name: "updatedAt"
      ),
      serverAttr(
        id: "\(recordingNamespace)/startedAtMs",
        namespace: recordingNamespace,
        name: "startedAtMs"
      ),
      serverAttr(
        id: "\(recordingNamespace)/durationSeconds",
        namespace: recordingNamespace,
        name: "durationSeconds"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/id",
        namespace: transcriptionNamespace,
        name: "id"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/wordCount",
        namespace: transcriptionNamespace,
        name: "wordCount"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/updatedAt",
        namespace: transcriptionNamespace,
        name: "updatedAt"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/transcriptText",
        namespace: transcriptionNamespace,
        name: "transcriptText"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/provider",
        namespace: transcriptionNamespace,
        name: "provider"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/segmentCount",
        namespace: transcriptionNamespace,
        name: "segmentCount"
      ),
      serverAttr(
        id: "\(transcriptionNamespace)/recording",
        namespace: transcriptionNamespace,
        name: "recording"
      ),
      serverAttr(id: "\(wordNamespace)/id", namespace: wordNamespace, name: "id"),
      serverAttr(id: "\(wordNamespace)/text", namespace: wordNamespace, name: "text"),
      serverAttr(id: "\(wordNamespace)/wordIndex", namespace: wordNamespace, name: "wordIndex"),
      serverAttr(
        id: "\(wordNamespace)/startTimeSeconds",
        namespace: wordNamespace,
        name: "startTimeSeconds"
      ),
      serverAttr(
        id: "\(wordNamespace)/endTimeSeconds",
        namespace: wordNamespace,
        name: "endTimeSeconds"
      ),
      serverAttr(id: "\(wordNamespace)/updatedAt", namespace: wordNamespace, name: "updatedAt"),
      serverAttr(
        id: "\(wordNamespace)/transcription",
        namespace: wordNamespace,
        name: "transcription"
      ),
      serverAttr(id: "\(wordNamespace)/recording", namespace: wordNamespace, name: "recording"),
    ]
  }

  /// Join-shaped live computation: parent recording + reverse-linked transcription.
  public static func liveJoinComputation(
    query: InstantLiveJSONValue,
    recordingID: String,
    title: String,
    transcriptionID: String,
    wordCount: Int,
    updatedAt: InstantTimestamp,
    processedTransactionID: String
  ) -> InstantLiveJSONValue {
    let ms = Double(updatedAt.milliseconds)
    return .object([
      "instaql-query": query,
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array([
                .array([
                  .array([
                    .string(recordingID),
                    .string("\(recordingNamespace)/id"),
                    .string(recordingID),
                    .number(ms),
                  ]),
                  .array([
                    .string(recordingID),
                    .string("\(recordingNamespace)/title"),
                    .string(title),
                    .number(ms),
                  ]),
                  .array([
                    .string(recordingID),
                    .string("\(recordingNamespace)/updatedAt"),
                    .number(ms),
                    .number(ms),
                  ]),
                ])
              ])
            ])
          ]),
          "child-nodes": .array([
            .object([
              "data": .object([
                "datalog-result": .object([
                  "join-rows": .array([
                    .array([
                      .array([
                        .string(transcriptionID),
                        .string("\(transcriptionNamespace)/id"),
                        .string(transcriptionID),
                        .number(ms),
                      ]),
                      .array([
                        .string(transcriptionID),
                        .string("\(transcriptionNamespace)/wordCount"),
                        .number(Double(wordCount)),
                        .number(ms),
                      ]),
                      .array([
                        .string(transcriptionID),
                        .string("\(transcriptionNamespace)/updatedAt"),
                        .number(ms),
                        .number(ms),
                      ]),
                      .array([
                        .string(transcriptionID),
                        .string("\(transcriptionNamespace)/recording"),
                        .string(recordingID),
                        .number(ms),
                      ]),
                    ])
                  ])
                ])
              ]),
              "child-nodes": .array([]),
            ])
          ]),
        ])
      ]),
      "processed-tx-id": .string(processedTransactionID),
    ])
  }

  public static func emptyLiveJoinComputation(query: InstantLiveJSONValue) -> InstantLiveJSONValue {
    .object([
      "instaql-query": query,
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array([])
            ])
          ]),
          "child-nodes": .array([]),
        ])
      ]),
    ])
  }

  private static func serverAttr(id: String, namespace: String, name: String) -> InstantLiveJSONValue {
    let isRef = name == "recording" || name == "transcription"
    let checked: String =
      if name == "updatedAt" {
        "date"
      } else if name.contains("Count") || name.contains("Seconds") || name.contains("Index")
        || name.hasSuffix("Ms")
      {
        "number"
      } else {
        "string"
      }
    return .object([
      "id": .string(id),
      "forward-identity": .array([
        .string("identity-\(id)"),
        .string(namespace),
        .string(name),
      ]),
      "value-type": .string(isRef ? "ref" : "blob"),
      "checked-data-type": .string(checked),
      "cardinality": .string("one"),
    ])
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
