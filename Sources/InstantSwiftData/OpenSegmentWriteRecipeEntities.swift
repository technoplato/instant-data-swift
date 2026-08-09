import Foundation
import InstantSwiftDataCore

// MARK: - Typed InstantEntityModel sketch for the open-segment write recipe
//
// Product apps declare their own entities (e.g. InstantRecording /
// InstantSegment). These recipe entities compile-check the *shape* under
// recipe_* namespaces without coupling the library to a consumer schema.
//
// Canonical prose: docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md
// Triple-op builders + words codec: InstantSwiftDataCore.OpenSegmentWriteRecipe

// MARK: - Recording

/// Minimal parent recording for the open-segment recipe example.
public struct OpenSegmentRecipeRecording: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var title: String
  public var ownerUserID: String
  public var updatedAtMs: Double

  public static let instantNamespace = OpenSegmentWriteRecipe.recordingNamespace
  public static let title = InstantAttributePath<Self, String>("title")
  public static let ownerUserID = InstantAttributePath<Self, String>("ownerUserID")
  public static let updatedAtMs = InstantAttributePath<Self, Double>("updatedAtMs")
  public static let owner = InstantAttributePath<Self, InstantID<Self>>("owner")
  public static let segments = InstantReverseRelation<Self, OpenSegmentRecipeSegment>(
    attribute: OpenSegmentRecipeSegment.recording
  )

  public static let instantAttributes = OpenSegmentWriteRecipe.recordingAttributes

  public init(
    id: InstantID<Self>,
    title: String,
    ownerUserID: String,
    updatedAtMs: Double
  ) {
    self.id = id
    self.title = title
    self.ownerUserID = ownerUserID
    self.updatedAtMs = updatedAtMs
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first,
      case let .string(ownerUserID) = snapshot.values["ownerUserID"]?.first,
      case let .number(updatedAtMs) = snapshot.values["updatedAtMs"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode open-segment recipe recording",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected title, ownerUserID, and updatedAtMs.",
        recovery: "Keep OpenSegmentRecipeRecording aligned with OpenSegmentWriteRecipe attributes."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.ownerUserID = ownerUserID
    self.updatedAtMs = updatedAtMs
  }
}

// MARK: - Segment

/// Open transcription segment: words live as strict JSON on this row.
public struct OpenSegmentRecipeSegment: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var recordingID: InstantID<OpenSegmentRecipeRecording>
  public var ownerUserID: String
  public var text: String
  public var wordsJSON: String
  public var wordCount: Double
  public var segmentIndex: Double
  public var isFinal: Bool
  public var startTimeSeconds: Double
  public var endTimeSeconds: Double
  public var updatedAtMs: Double

  public static let instantNamespace = OpenSegmentWriteRecipe.segmentNamespace
  public static let recording = InstantAttributePath<
    Self, InstantID<OpenSegmentRecipeRecording>
  >("recording")
  public static let recordingID = InstantAttributePath<Self, String>("recordingID")
  public static let ownerUserID = InstantAttributePath<Self, String>("ownerUserID")
  public static let text = InstantAttributePath<Self, String>("text")
  public static let wordsJSON = InstantAttributePath<Self, String>("wordsJSON")
  public static let wordCount = InstantAttributePath<Self, Double>("wordCount")
  public static let segmentIndex = InstantAttributePath<Self, Double>("segmentIndex")
  public static let isFinal = InstantAttributePath<Self, Bool>("isFinal")
  public static let startTimeSeconds = InstantAttributePath<Self, Double>("startTimeSeconds")
  public static let endTimeSeconds = InstantAttributePath<Self, Double>("endTimeSeconds")
  public static let updatedAtMs = InstantAttributePath<Self, Double>("updatedAtMs")
  public static let owner = InstantAttributePath<Self, InstantID<Self>>("owner")

  public static let instantAttributes = OpenSegmentWriteRecipe.segmentAttributes

  public init(
    id: InstantID<Self>,
    recordingID: InstantID<OpenSegmentRecipeRecording>,
    ownerUserID: String,
    text: String,
    wordsJSON: String,
    wordCount: Double,
    segmentIndex: Double,
    isFinal: Bool,
    startTimeSeconds: Double,
    endTimeSeconds: Double,
    updatedAtMs: Double
  ) {
    self.id = id
    self.recordingID = recordingID
    self.ownerUserID = ownerUserID
    self.text = text
    self.wordsJSON = wordsJSON
    self.wordCount = wordCount
    self.segmentIndex = segmentIndex
    self.isFinal = isFinal
    self.startTimeSeconds = startTimeSeconds
    self.endTimeSeconds = endTimeSeconds
    self.updatedAtMs = updatedAtMs
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    let recordingRaw: String
    if case let .ref(id) = snapshot.values["recording"]?.first {
      recordingRaw = id
    } else if case let .string(id) = snapshot.values["recordingID"]?.first {
      recordingRaw = id
    } else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode open-segment recipe segment",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected recording ref or recordingID string.",
        recovery: "Keep OpenSegmentRecipeSegment aligned with OpenSegmentWriteRecipe attributes."
      )
    }
    guard case let .string(ownerUserID) = snapshot.values["ownerUserID"]?.first,
      case let .string(text) = snapshot.values["text"]?.first,
      case let .string(wordsJSON) = snapshot.values["wordsJSON"]?.first,
      case let .number(wordCount) = snapshot.values["wordCount"]?.first,
      case let .number(segmentIndex) = snapshot.values["segmentIndex"]?.first,
      case let .bool(isFinal) = snapshot.values["isFinal"]?.first,
      case let .number(startTimeSeconds) = snapshot.values["startTimeSeconds"]?.first,
      case let .number(endTimeSeconds) = snapshot.values["endTimeSeconds"]?.first,
      case let .number(updatedAtMs) = snapshot.values["updatedAtMs"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode open-segment recipe segment",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message:
          "Expected ownerUserID, text, wordsJSON, counts, times, isFinal, and updatedAtMs.",
        recovery: "Keep OpenSegmentRecipeSegment aligned with OpenSegmentWriteRecipe attributes."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    recordingID = InstantID(rawValue: recordingRaw)
    self.ownerUserID = ownerUserID
    self.text = text
    self.wordsJSON = wordsJSON
    self.wordCount = wordCount
    self.segmentIndex = segmentIndex
    self.isFinal = isFinal
    self.startTimeSeconds = startTimeSeconds
    self.endTimeSeconds = endTimeSeconds
    self.updatedAtMs = updatedAtMs
  }

  /// Decode words from `wordsJSON` (strict / loud).
  public func words() throws -> [OpenSegmentWord] {
    try OpenSegmentWriteRecipe.decodeWordsJSON(wordsJSON)
  }
}

// MARK: - Typed mutation builders

/// App-facing InstantMutation builders for the open-segment recipe entities.
///
/// Use with `client.transact` / `InstantMutationBatch` / `send`. Success means
/// local materialize + durable outbox only — never server ack.
public enum OpenSegmentWriteRecipeTyped: Sendable {
  /// Ensure parent recording (title + owner scalar + owner link + updatedAtMs).
  public static func ensureRecordingMutation(
    recordingID: InstantID<OpenSegmentRecipeRecording>,
    title: String,
    ownerUserID: String,
    updatedAtMs: Double,
    linkOwnerRef: Bool = true
  ) -> InstantMutation {
    var assignments: [InstantAttributeAssignment<OpenSegmentRecipeRecording>] = [
      OpenSegmentRecipeRecording.title.set(title),
      OpenSegmentRecipeRecording.ownerUserID.set(ownerUserID),
      OpenSegmentRecipeRecording.updatedAtMs.set(updatedAtMs),
    ]
    if linkOwnerRef {
      // Owner link targets $users; recipe uses the user id string as entity id.
      assignments.append(
        OpenSegmentRecipeRecording.owner.set(
          InstantID<OpenSegmentRecipeRecording>(rawValue: ownerUserID)
        )
      )
    }
    return OpenSegmentRecipeRecording.update(id: recordingID, assignments)
  }

  /// Upsert the open segment only (words encoded strictly).
  public static func openSegmentUpsertMutation(
    segmentID: InstantID<OpenSegmentRecipeSegment>,
    recordingID: InstantID<OpenSegmentRecipeRecording>,
    ownerUserID: String,
    text: String,
    words: [OpenSegmentWord],
    segmentIndex: Int,
    isFinal: Bool,
    startTimeSeconds: Double,
    endTimeSeconds: Double,
    updatedAtMs: Double,
    linkOwnerRef: Bool = true
  ) throws -> InstantMutation {
    let wordsJSON = try OpenSegmentWriteRecipe.encodeWordsJSON(words)
    var assignments: [InstantAttributeAssignment<OpenSegmentRecipeSegment>] = [
      OpenSegmentRecipeSegment.recording.set(recordingID),
      OpenSegmentRecipeSegment.recordingID.set(recordingID.rawValue),
      OpenSegmentRecipeSegment.ownerUserID.set(ownerUserID),
      OpenSegmentRecipeSegment.text.set(text),
      OpenSegmentRecipeSegment.wordsJSON.set(wordsJSON),
      OpenSegmentRecipeSegment.wordCount.set(Double(words.count)),
      OpenSegmentRecipeSegment.segmentIndex.set(Double(segmentIndex)),
      OpenSegmentRecipeSegment.isFinal.set(isFinal),
      OpenSegmentRecipeSegment.startTimeSeconds.set(startTimeSeconds),
      OpenSegmentRecipeSegment.endTimeSeconds.set(endTimeSeconds),
      OpenSegmentRecipeSegment.updatedAtMs.set(updatedAtMs),
    ]
    if linkOwnerRef {
      assignments.append(
        OpenSegmentRecipeSegment.owner.set(
          InstantID<OpenSegmentRecipeSegment>(rawValue: ownerUserID)
        )
      )
    }
    return OpenSegmentRecipeSegment.update(id: segmentID, assignments)
  }

  /// Full batch: optional ensure-recording + open-segment upsert.
  public static func mutations(
    for fields: OpenSegmentWriteFields,
    linkOwnerRef: Bool = true
  ) throws -> [InstantMutation] {
    var result: [InstantMutation] = []
    let recordingID = InstantID<OpenSegmentRecipeRecording>(rawValue: fields.recordingID)
    let segmentID = InstantID<OpenSegmentRecipeSegment>(rawValue: fields.segmentID)
    if let title = fields.ensureRecordingTitle {
      result.append(
        ensureRecordingMutation(
          recordingID: recordingID,
          title: title,
          ownerUserID: fields.ownerUserID,
          updatedAtMs: fields.updatedAtMs,
          linkOwnerRef: linkOwnerRef
        )
      )
    }
    result.append(
      try openSegmentUpsertMutation(
        segmentID: segmentID,
        recordingID: recordingID,
        ownerUserID: fields.ownerUserID,
        text: fields.text,
        words: fields.words,
        segmentIndex: fields.segmentIndex,
        isFinal: fields.isFinal,
        startTimeSeconds: fields.startTimeSeconds,
        endTimeSeconds: fields.endTimeSeconds,
        updatedAtMs: fields.updatedAtMs,
        linkOwnerRef: linkOwnerRef
      )
    )
    return result
  }
}
