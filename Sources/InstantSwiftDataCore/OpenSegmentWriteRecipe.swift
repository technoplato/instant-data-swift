import Foundation

// MARK: - ADR 0015 open-segment write recipe (#155)
//
// First-class library recipe for high-churn live speech: ensure one recording
// row, upsert only the open transcription segment, store words as strict
// Codable JSON on the segment. transact = local materialize + durable outbox
// only (never server ack).
//
// Docs: docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md
// Typed InstantEntityModel sketch: InstantSwiftData/OpenSegmentWriteRecipeEntities.swift
//
// Outbox same-entity supersession is wired at durable enqueue for only the one
// exact never-offered tail with the same complete scalar assignment shape.
// Establish recording/owner refs once as a relation-bearing ordering barrier;
// only later scalar-only, identical-shape segment assignments can supersede.
// Always outbox every interim write; barriers remain durable and ordered.

// MARK: - Words (strict Codable JSON)

/// One timed speech word stored inside segment `wordsJSON`.
///
/// Wire shape is intentionally small and stable: `start`, `end`, `text`.
/// Apps may version additional fields later; decode failures must be loud.
public struct OpenSegmentWord: Codable, Equatable, Hashable, Sendable {
  public var start: Double
  public var end: Double
  public var text: String

  public init(start: Double, end: Double, text: String) {
    self.start = start
    self.end = end
    self.text = text
  }
}

/// Field snapshot for one open-segment upsert (domain → Instant row fields).
///
/// Apps map speech state into this shape; Instant only sees the resulting
/// mutations. No previous full-document graph.
public struct OpenSegmentWriteFields: Equatable, Sendable {
  public var recordingID: String
  public var segmentID: String
  public var ownerUserID: String
  public var segmentIndex: Int
  public var text: String
  public var words: [OpenSegmentWord]
  public var isFinal: Bool
  public var startTimeSeconds: Double
  public var endTimeSeconds: Double
  public var updatedAtMs: Double
  /// When non-nil, include ensure-recording ops for this write batch.
  public var ensureRecordingTitle: String?

  public init(
    recordingID: String,
    segmentID: String,
    ownerUserID: String,
    segmentIndex: Int,
    text: String,
    words: [OpenSegmentWord],
    isFinal: Bool,
    startTimeSeconds: Double,
    endTimeSeconds: Double,
    updatedAtMs: Double,
    ensureRecordingTitle: String? = nil
  ) {
    self.recordingID = recordingID
    self.segmentID = segmentID
    self.ownerUserID = ownerUserID
    self.segmentIndex = segmentIndex
    self.text = text
    self.words = words
    self.isFinal = isFinal
    self.startTimeSeconds = startTimeSeconds
    self.endTimeSeconds = endTimeSeconds
    self.updatedAtMs = updatedAtMs
    self.ensureRecordingTitle = ensureRecordingTitle
  }
}

// MARK: - Recipe (schema + mutations)

/// Compile-checked open-segment write recipe for Instant Swift Data.
///
/// Product apps may use their own namespaces/attribute names; the **shape** is
/// the contract: recording ensure once, one segment upsert, wordsJSON, owner,
/// updatedAtMs, always outbox via `transact`. The compatibility builders below
/// include relationship refs and therefore establish barriers; high-frequency
/// supersession starts with later scalar-only assignments built by the app's
/// typed entity mutations.
public enum OpenSegmentWriteRecipe: Sendable {
  public static let recordingNamespace = "recipe_recordings"
  public static let segmentNamespace = "recipe_transcription_segments"

  /// Recipe schema attributes (recording + segment). Suitable for local
  /// bootstrap fixtures and architecture tests.
  public static var attributes: [InstantAttribute] {
    recordingAttributes + segmentAttributes
  }

  public static var recordingAttributes: [InstantAttribute] {
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
        id: "\(recordingNamespace)/ownerUserID",
        namespace: recordingNamespace,
        name: "ownerUserID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(recordingNamespace)/updatedAtMs",
        namespace: recordingNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(recordingNamespace)/owner",
        namespace: recordingNamespace,
        name: "owner",
        valueType: .ref,
        isRequired: false,
        isIndexed: true,
        forwardIdentity: "\(recordingNamespace)/owner",
        reverseIdentity: "$users/recipeRecordings",
        linkNamespace: "$users"
      ),
    ]
  }

  public static var segmentAttributes: [InstantAttribute] {
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
        id: "\(segmentNamespace)/ownerUserID",
        namespace: segmentNamespace,
        name: "ownerUserID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/text",
        namespace: segmentNamespace,
        name: "text",
        valueType: .string
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/wordsJSON",
        namespace: segmentNamespace,
        name: "wordsJSON",
        valueType: .string
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/wordCount",
        namespace: segmentNamespace,
        name: "wordCount",
        valueType: .number,
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
        id: "\(segmentNamespace)/isFinal",
        namespace: segmentNamespace,
        name: "isFinal",
        valueType: .boolean,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/startTimeSeconds",
        namespace: segmentNamespace,
        name: "startTimeSeconds",
        valueType: .number
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/endTimeSeconds",
        namespace: segmentNamespace,
        name: "endTimeSeconds",
        valueType: .number
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/updatedAtMs",
        namespace: segmentNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/recording",
        namespace: segmentNamespace,
        name: "recording",
        valueType: .ref,
        isRequired: true,
        isIndexed: true,
        forwardIdentity: "\(segmentNamespace)/recording",
        reverseIdentity: "\(recordingNamespace)/segments",
        linkNamespace: recordingNamespace,
        onDelete: .cascade
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/owner",
        namespace: segmentNamespace,
        name: "owner",
        valueType: .ref,
        isRequired: false,
        isIndexed: true,
        forwardIdentity: "\(segmentNamespace)/owner",
        reverseIdentity: "$users/recipeSegments",
        linkNamespace: "$users"
      ),
    ]
  }

  // MARK: Words JSON (strict / loud)

  private static let wordsEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let wordsDecoder = JSONDecoder()

  /// Encode words as a UTF-8 JSON array string. Throws on encode failure.
  /// Encode words as JSON text for a string `wordsJSON` column.
  /// Prefer `[OpenSegmentWord].JSONStringRepresentation` at the typed attribute
  /// layer when available; this Core helper stays dependency-free.
  public static func encodeWordsJSON(_ words: [OpenSegmentWord]) throws -> String {
    do {
      let data = try wordsEncoder.encode(words)
      guard let string = String(data: data, encoding: .utf8) else {
        throw InstantError(
          code: .decodeFailed,
          operation: "encode open-segment wordsJSON",
          namespace: segmentNamespace,
          path: "wordsJSON",
          message: "Encoded words JSON was not valid UTF-8.",
          recovery: "Keep OpenSegmentWord Codable and use UTF-8 JSON only."
        )
      }
      return string
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .decodeFailed,
        operation: "encode open-segment wordsJSON",
        namespace: segmentNamespace,
        path: "wordsJSON",
        message: "Failed to encode open-segment words: \(error)",
        recovery: "Keep OpenSegmentWord Codable fields stable; do not use try?."
      )
    }
  }

  /// Decode a UTF-8 JSON array string into words. Throws on decode failure.
  public static func decodeWordsJSON(_ json: String) throws -> [OpenSegmentWord] {
    guard let data = json.data(using: .utf8) else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode open-segment wordsJSON",
        namespace: segmentNamespace,
        path: "wordsJSON",
        message: "wordsJSON is not valid UTF-8.",
        recovery: "Store wordsJSON as a UTF-8 JSON array of {start,end,text}."
      )
    }
    do {
      return try wordsDecoder.decode([OpenSegmentWord].self, from: data)
    } catch {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode open-segment wordsJSON",
        namespace: segmentNamespace,
        path: "wordsJSON",
        message: "Failed to decode open-segment words: \(error)",
        recovery: "Align the stored JSON with OpenSegmentWord (start, end, text)."
      )
    }
  }

  // MARK: Mutations

  /// Ensure the parent recording row exists / is refreshed (once per session).
  ///
  /// Idempotent upsert of identity + title + owner + updatedAtMs. Does not
  /// touch segments. Call when opening a recording; optional on every speech
  /// batch when summary fields change.
  public static func ensureRecordingOperations(
    recordingID: String,
    title: String,
    ownerUserID: String,
    updatedAtMs: Double,
    transactionID: String,
    linkOwnerRef: Bool = true
  ) -> [InstantTripleOperation] {
    let txTime = InstantTimestamp(milliseconds: Int64(updatedAtMs))
    var operations: [InstantTripleOperation] = [
      identityOperation(
        id: recordingID,
        namespace: recordingNamespace,
        updatedAt: txTime,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: recordingID,
          attributeID: "\(recordingNamespace)/title",
          value: .string(title),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: recordingID,
          attributeID: "\(recordingNamespace)/ownerUserID",
          value: .string(ownerUserID),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: recordingID,
          attributeID: "\(recordingNamespace)/updatedAtMs",
          value: .number(updatedAtMs),
          txID: transactionID,
          txTime: txTime
        )
      ),
    ]
    if linkOwnerRef {
      operations.append(
        .insert(
          InstantTriple(
            entityID: recordingID,
            attributeID: "\(recordingNamespace)/owner",
            value: .ref(ownerUserID),
            txID: transactionID,
            txTime: txTime
          )
        )
      )
    }
    return operations
  }

  /// Upsert **only** the open segment row, including its recording relation.
  ///
  /// This relation-bearing compatibility builder is for initial creation or
  /// repair and is intentionally an outbox ordering barrier. Even when
  /// `linkOwnerRef` is false, the recording ref remains. For a high-frequency
  /// interim loop, call this once, then submit complete scalar-only assignments
  /// with the same attribute set on every later write.
  public static func openSegmentUpsertOperations(
    segmentID: String,
    recordingID: String,
    ownerUserID: String,
    text: String,
    wordsJSON: String,
    wordCount: Int,
    segmentIndex: Int,
    isFinal: Bool,
    startTimeSeconds: Double,
    endTimeSeconds: Double,
    updatedAtMs: Double,
    transactionID: String,
    linkOwnerRef: Bool = true
  ) -> [InstantTripleOperation] {
    let txTime = InstantTimestamp(milliseconds: Int64(updatedAtMs))
    var operations: [InstantTripleOperation] = [
      identityOperation(
        id: segmentID,
        namespace: segmentNamespace,
        updatedAt: txTime,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/recordingID",
          value: .string(recordingID),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/ownerUserID",
          value: .string(ownerUserID),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/text",
          value: .string(text),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/wordsJSON",
          value: .string(wordsJSON),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/wordCount",
          value: .number(Double(wordCount)),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/segmentIndex",
          value: .number(Double(segmentIndex)),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/isFinal",
          value: .bool(isFinal),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/startTimeSeconds",
          value: .number(startTimeSeconds),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/endTimeSeconds",
          value: .number(endTimeSeconds),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/updatedAtMs",
          value: .number(updatedAtMs),
          txID: transactionID,
          txTime: txTime
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(segmentNamespace)/recording",
          value: .ref(recordingID),
          txID: transactionID,
          txTime: txTime
        )
      ),
    ]
    if linkOwnerRef {
      operations.append(
        .insert(
          InstantTriple(
            entityID: segmentID,
            attributeID: "\(segmentNamespace)/owner",
            value: .ref(ownerUserID),
            txID: transactionID,
            txTime: txTime
          )
        )
      )
    }
    return operations
  }

  /// Build the full open-segment write batch from a field snapshot.
  ///
  /// Encodes words strictly. Includes ensure-recording ops when
  /// `ensureRecordingTitle` is set. This compatibility batch includes the
  /// segment recording ref, so it is a durable barrier rather than a
  /// supersession-eligible interim shape.
  public static func operations(
    for fields: OpenSegmentWriteFields,
    transactionID: String,
    linkOwnerRef: Bool = true
  ) throws -> [InstantTripleOperation] {
    let wordsJSON = try encodeWordsJSON(fields.words)
    var operations: [InstantTripleOperation] = []
    if let title = fields.ensureRecordingTitle {
      operations += ensureRecordingOperations(
        recordingID: fields.recordingID,
        title: title,
        ownerUserID: fields.ownerUserID,
        updatedAtMs: fields.updatedAtMs,
        transactionID: transactionID,
        linkOwnerRef: linkOwnerRef
      )
    }
    operations += openSegmentUpsertOperations(
      segmentID: fields.segmentID,
      recordingID: fields.recordingID,
      ownerUserID: fields.ownerUserID,
      text: fields.text,
      wordsJSON: wordsJSON,
      wordCount: fields.words.count,
      segmentIndex: fields.segmentIndex,
      isFinal: fields.isFinal,
      startTimeSeconds: fields.startTimeSeconds,
      endTimeSeconds: fields.endTimeSeconds,
      updatedAtMs: fields.updatedAtMs,
      transactionID: transactionID,
      linkOwnerRef: linkOwnerRef
    )
    return operations
  }

  // MARK: Observation plans (bounded)

  /// Segments for one recording, ordered by segment index (active transcript).
  public static func segmentsForRecordingQuery(
    recordingID: String,
    limit: Int? = nil
  ) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "recipe.open-segment.segments-for-recording",
      namespace: segmentNamespace,
      filters: [.equals(field: "recordingID", value: .string(recordingID))],
      order: InstantQueryOrder("segmentIndex", .ascending),
      limit: limit
    )
  }

  /// Single open segment by id.
  public static func openSegmentQuery(segmentID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "recipe.open-segment.one",
      namespace: segmentNamespace,
      filters: [.equals(field: "id", value: .string(segmentID))],
      limit: 1
    )
  }

  // MARK: Private helpers

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
}
