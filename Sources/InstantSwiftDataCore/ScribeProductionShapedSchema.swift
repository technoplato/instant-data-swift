import Foundation

/// Production Scribe Instant namespaces and a thrash-shaped `debugLogs` second store.
///
/// Issue #150 and field 2026-08-05: the linked-infinite recipe used
/// `linked_infinite_*` toy namespaces, so multi‑GB idle thrash on real Scribe
/// shapes (recordings / transcriptionWords / dual Instant debugLogs) kept
/// rediscovering itself. Soak gates and dual-write thrash drivers must use these
/// production names — not a renamed toy graph.
///
/// Attribute coverage is intentionally a **lower-bound materialization mirror**
/// of `realtime-voice-sqlite-instant/instant.schema.ts` (not every optional JSON
/// field). Enough attrs per entity that outbox steps and dual residency match
/// production cost class.
public enum ScribeProductionShapedSchema: Sendable {
  public static let recordingNamespace = "recordings"
  public static let transcriptionNamespace = "transcriptions"
  public static let wordNamespace = "transcriptionWords"
  public static let segmentNamespace = "transcriptionSegments"
  public static let attachmentNamespace = "recordingAttachments"
  public static let debugLogsNamespace = "debugLogs"

  /// Multi-attr debugLogs entity shape (InstantDBLogger field thrash: ~20–22 ops/row).
  public static let debugLogAttributeNames: [String] = [
    "timestampMs",
    "timestampLocal",
    "level",
    "subsystem",
    "category",
    "name",
    "message",
    "metadataJSON",
    "sessionID",
    "platform",
    "deviceName",
    "appVersion",
    "buildCommit",
    "buildBranch",
    "buildIsDirty",
    "contributingPathsJSON",
    "issueReferencesJSON",
    "projectName",
    "fileID",
    "function",
    "sourceLine",
  ]

  public static var attributes: [InstantAttribute] {
    recordingAttributes
      + transcriptionAttributes
      + wordAttributes
      + segmentAttributes
      + attachmentAttributes
  }

  public static var debugLogsAttributes: [InstantAttribute] {
    var attrs: [InstantAttribute] = [.primaryKey(namespace: debugLogsNamespace)]
    for name in debugLogAttributeNames {
      let valueType: InstantValueType
      switch name {
      case "timestampMs", "sourceLine":
        valueType = .number
      case "buildIsDirty":
        valueType = .boolean
      default:
        valueType = .string
      }
      let indexed = [
        "timestampMs", "level", "category", "name", "sessionID", "platform",
        "buildBranch", "buildIsDirty", "projectName",
      ].contains(name)
      attrs.append(
        InstantAttribute(
          id: "\(debugLogsNamespace)/\(name)",
          namespace: debugLogsNamespace,
          name: name,
          valueType: valueType,
          isIndexed: indexed
        )
      )
    }
    return attrs
  }

  // MARK: - Namespace attributes

  private static var recordingAttributes: [InstantAttribute] {
    [
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
      InstantAttribute(
        id: "\(recordingNamespace)/updatedAtMs",
        namespace: recordingNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  private static var transcriptionAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: transcriptionNamespace),
      InstantAttribute(
        id: "\(transcriptionNamespace)/recordingID",
        namespace: transcriptionNamespace,
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(transcriptionNamespace)/wordCount",
        namespace: transcriptionNamespace,
        name: "wordCount",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(transcriptionNamespace)/segmentCount",
        namespace: transcriptionNamespace,
        name: "segmentCount",
        valueType: .number
      ),
      InstantAttribute(
        id: "\(transcriptionNamespace)/provider",
        namespace: transcriptionNamespace,
        name: "provider",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(transcriptionNamespace)/transcriptText",
        namespace: transcriptionNamespace,
        name: "transcriptText",
        valueType: .string
      ),
      InstantAttribute(
        id: "\(transcriptionNamespace)/updatedAt",
        namespace: transcriptionNamespace,
        name: "updatedAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(transcriptionNamespace)/updatedAtMs",
        namespace: transcriptionNamespace,
        name: "updatedAtMs",
        valueType: .number,
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
  }

  private static var wordAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: wordNamespace),
      InstantAttribute(
        id: "\(wordNamespace)/text",
        namespace: wordNamespace,
        name: "text",
        valueType: .string
        // Not indexed in production instant.schema.ts (aev on unique word strings
        // was a false-confidence memory amplifier in the soak / #044).
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
        id: "\(wordNamespace)/recordingID",
        namespace: wordNamespace,
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(wordNamespace)/transcriptionID",
        namespace: wordNamespace,
        name: "transcriptionID",
        valueType: .string,
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
  }

  private static var segmentAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: segmentNamespace),
      InstantAttribute(
        id: "\(segmentNamespace)/recordingID",
        namespace: segmentNamespace,
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/transcriptionID",
        namespace: segmentNamespace,
        name: "transcriptionID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/segmentIndex",
        namespace: segmentNamespace,
        name: "segmentIndex",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/text",
        namespace: segmentNamespace,
        name: "text",
        valueType: .string
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/wordCount",
        namespace: segmentNamespace,
        name: "wordCount",
        valueType: .number
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/updatedAtMs",
        namespace: segmentNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  private static var attachmentAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: attachmentNamespace),
      InstantAttribute(
        id: "\(attachmentNamespace)/recordingID",
        namespace: attachmentNamespace,
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(attachmentNamespace)/kind",
        namespace: attachmentNamespace,
        name: "kind",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(attachmentNamespace)/byteCount",
        namespace: attachmentNamespace,
        name: "byteCount",
        valueType: .number
      ),
      InstantAttribute(
        id: "\(attachmentNamespace)/fileExtension",
        namespace: attachmentNamespace,
        name: "fileExtension",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(attachmentNamespace)/updatedAtMs",
        namespace: attachmentNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  // MARK: - Queries

  /// Scribe library list shape: page 50 parents + transcription metrics.
  public static func scribeShapedListQuery(pageSize: Int = 50) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "scribe-production.recordings.list",
      namespace: recordingNamespace,
      order: InstantQueryOrder("updatedAt", .descending),
      limit: pageSize,
      includes: [
        InstantQueryInclude(
          "transcriptions",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "scribe-production.included-transcriptions",
            namespace: transcriptionNamespace,
            order: InstantQueryOrder("updatedAt", .descending),
            selectedFields: [
              "wordCount",
              "updatedAt",
              "recording",
              "transcriptText",
              "provider",
              "segmentCount",
              "recordingID",
            ]
          )
        ),
      ]
    )
  }

  // MARK: - Operations

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
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(recordingNamespace)/updatedAtMs",
          value: .number(Double(updatedAt.milliseconds)),
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
          attributeID: "\(transcriptionNamespace)/recordingID",
          value: .string(recordingID),
          txID: transactionID,
          txTime: updatedAt
        )
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
          attributeID: "\(transcriptionNamespace)/updatedAtMs",
          value: .number(Double(updatedAt.milliseconds)),
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
          attributeID: "\(wordNamespace)/recordingID",
          value: .string(recordingID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(wordNamespace)/transcriptionID",
          value: .string(transcriptionID),
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

  public static func createSegmentOperations(
    id: String,
    recordingID: String,
    transcriptionID: String,
    segmentIndex: Int,
    text: String,
    wordCount: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: segmentNamespace),
      identityOperation(
        id: id,
        namespace: segmentNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(segmentNamespace)/recordingID",
          value: .string(recordingID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(segmentNamespace)/transcriptionID",
          value: .string(transcriptionID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(segmentNamespace)/segmentIndex",
          value: .number(Double(segmentIndex)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(segmentNamespace)/text",
          value: .string(text),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(segmentNamespace)/wordCount",
          value: .number(Double(wordCount)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(segmentNamespace)/updatedAtMs",
          value: .number(Double(updatedAt.milliseconds)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func createAttachmentOperations(
    id: String,
    recordingID: String,
    kind: String,
    byteCount: Int,
    fileExtension: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: attachmentNamespace),
      identityOperation(
        id: id,
        namespace: attachmentNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(attachmentNamespace)/recordingID",
          value: .string(recordingID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(attachmentNamespace)/kind",
          value: .string(kind),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(attachmentNamespace)/byteCount",
          value: .number(Double(byteCount)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(attachmentNamespace)/fileExtension",
          value: .string(fileExtension),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(attachmentNamespace)/updatedAtMs",
          value: .number(Double(updatedAt.milliseconds)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  /// One multi-attr debugLogs entity (~22 ops) — field thrash unit from InstantDBLogger.
  public static func createDebugLogOperations(
    id: String,
    batchIndex: Int,
    entityIndex: Int,
    updatedAt: InstantTimestamp,
    transactionID: String,
    eventName: String = "outbox.flush.head-of-line-wait",
    message: String = "Simulated dual-write debug log row"
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = [
      .requireEntityMissing(entityID: id, namespace: debugLogsNamespace),
      identityOperation(
        id: id,
        namespace: debugLogsNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
    ]
    let stringValues: [String: String] = [
      "timestampLocal": "2026-08-05 19:28:00 EDT",
      "level": "notice",
      "subsystem": "com.michaellustig.scribe",
      "category": "instant-library.outbox",
      "name": eventName,
      "message": message,
      "metadataJSON":
        "{\"mutationID\":\"debug-log-batch-\(batchIndex)\",\"entityIndex\":\"\(entityIndex)\"}",
      "sessionID": "soak-session",
      "platform": "iOS",
      "deviceName": "iPad",
      "appVersion": "0.1 (soak)",
      "buildCommit": "soak",
      "buildBranch": "main",
      "contributingPathsJSON": "[]",
      "issueReferencesJSON": "[]",
      "projectName": "Scribe",
      "fileID": "InstantRuntime.swift",
      "function": "sendMutations(_:)",
    ]
    for (name, value) in stringValues {
      operations.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(debugLogsNamespace)/\(name)",
            value: .string(value),
            txID: transactionID,
            txTime: updatedAt
          )
        )
      )
    }
    operations.append(
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(debugLogsNamespace)/timestampMs",
          value: .number(Double(updatedAt.milliseconds)),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    )
    operations.append(
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(debugLogsNamespace)/sourceLine",
          value: .number(1_149),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    )
    operations.append(
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(debugLogsNamespace)/buildIsDirty",
          value: .bool(false),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    )
    return operations
  }

  /// Seed recordings → transcriptions → words → segments → attachments.
  public static func soakOperations(
    profile: LinkedInfiniteScribeShapedSoakProfile,
    recordingIDs: [String],
    transcriptionIDs: [String],
    wordIDsByRecording: [[String]],
    segmentIDsByRecording: [[String]],
    attachmentIDsByRecording: [[String]],
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
      let title = "Recording \(String(format: "%03d", index + 1)) — production soak"
      let wordIDs = wordIDsByRecording[index]
      let segmentIDs =
        index < segmentIDsByRecording.count ? segmentIDsByRecording[index] : []
      let attachmentIDs =
        index < attachmentIDsByRecording.count ? attachmentIDsByRecording[index] : []
      operations += createRecordingOperations(
        id: recordingIDs[index],
        title: title,
        updatedAt: offset,
        transactionID: transactionID,
        startedAtMs: Double(offset.milliseconds),
        durationSeconds: Double(profile.wordsPerRecording) * 0.25
      )
      operations += createTranscriptionOperations(
        id: transcriptionIDs[index],
        recordingID: recordingIDs[index],
        wordCount: wordIDs.count,
        updatedAt: offset,
        transactionID: transactionID,
        transcriptText: transcriptText,
        segmentCount: max(1, segmentIDs.count)
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
      for (segmentIndex, segmentID) in segmentIDs.enumerated() {
        operations += createSegmentOperations(
          id: segmentID,
          recordingID: recordingIDs[index],
          transcriptionID: transcriptionIDs[index],
          segmentIndex: segmentIndex,
          text: "segment \(segmentIndex)",
          wordCount: max(1, wordIDs.count / max(1, segmentIDs.count)),
          updatedAt: offset,
          transactionID: transactionID
        )
      }
      for (attachmentIndex, attachmentID) in attachmentIDs.enumerated() {
        operations += createAttachmentOperations(
          id: attachmentID,
          recordingID: recordingIDs[index],
          kind: attachmentIndex % 2 == 0 ? "audio" : "image",
          byteCount: 1_024 * (attachmentIndex + 1),
          fileExtension: attachmentIndex % 2 == 0 ? "m4a" : "jpg",
          updatedAt: offset,
          transactionID: transactionID
        )
      }
    }
    return operations
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
        attributeID: "\(namespace)/id",
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }
}
