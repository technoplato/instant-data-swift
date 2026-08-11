import Foundation
import InstantSwiftData

// MARK: - recording.create (public start-record name)

public struct RecordingCreated: Hashable, Sendable {
  public var recordingID: InstantID<Recording>
  public var transcriptionID: InstantID<Transcription>
  public var openSegmentID: InstantID<Segment>
}

/// Public start-record mutation. Owned transcription + empty open speech segment
/// are implementation of start-record — not a second public name (Q22).
public struct CreateRecording: InstantMessage {
  public var recordingID: InstantID<Recording>
  public var transcriptionID: InstantID<Transcription>
  public var openSegmentID: InstantID<Segment>
  public var title: String
  public var now: Date

  public init(
    recordingID: InstantID<Recording> = InstantID(),
    transcriptionID: InstantID<Transcription> = InstantID(),
    openSegmentID: InstantID<Segment> = InstantID(),
    title: String,
    now: Date = .now
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.openSegmentID = openSegmentID
    self.title = title
    self.now = now
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RecordingCreated>
  {
    _ = client
    return InstantPreparedMessage(
      change: RecordingCreated(
        recordingID: recordingID,
        transcriptionID: transcriptionID,
        openSegmentID: openSegmentID
      )
    ) {
      Recording.create(
        id: recordingID,
        Recording.title.set(title),
        Recording.createdAt.set(now),
        Recording.updatedAt.set(now),
        Recording.durationMilliseconds.set(0)
      )
      Transcription.create(
        id: transcriptionID,
        Transcription.recording.set(recordingID),
        Transcription.createdAt.set(now),
        Transcription.updatedAt.set(now)
      )
      Segment.create(
        id: openSegmentID,
        Segment.transcription.set(transcriptionID),
        Segment.index.set(0),
        Segment.wallStart.set(now),
        Segment.wallEnd.set(now),
        Segment.relativeStartMilliseconds.set(0),
        Segment.relativeEndMilliseconds.set(0),
        Segment.bodyKind.set("speech"),
        Segment.wordsJSON.set("[]"),
        Segment.text.set(""),
        Segment.isFinal.set(false)
      )
    }
  }
}

// MARK: - stopRecording finish fields

public struct RecordingFinished: Hashable, Sendable {
  public var recordingID: InstantID<Recording>
  public var transcriptionID: InstantID<Transcription>
}

public struct FinishRecording: InstantMessage {
  public var recordingID: InstantID<Recording>
  public var transcriptionID: InstantID<Transcription>
  public var finishedAt: Date
  public var durationMilliseconds: Int

  public init(
    recordingID: InstantID<Recording>,
    transcriptionID: InstantID<Transcription>,
    finishedAt: Date = .now,
    durationMilliseconds: Int
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.finishedAt = finishedAt
    self.durationMilliseconds = durationMilliseconds
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RecordingFinished>
  {
    _ = client
    return InstantPreparedMessage(
      change: RecordingFinished(recordingID: recordingID, transcriptionID: transcriptionID)
    ) {
      Recording.updateExisting(
        id: recordingID,
        Recording.finishedAt.set(finishedAt),
        Recording.updatedAt.set(finishedAt),
        Recording.durationMilliseconds.set(durationMilliseconds)
      )
      Transcription.updateExisting(
        id: transcriptionID,
        Transcription.finishedAt.set(finishedAt),
        Transcription.updatedAt.set(finishedAt)
      )
    }
  }
}

// MARK: - speechRecognized (open-segment upsert + when isFinal)

public struct SpeechUpserted: Hashable, Sendable {
  public var segmentID: InstantID<Segment>
  public var isFinal: Bool
  public var nextOpenSegmentID: InstantID<Segment>?
}

public struct UpsertSpeechSegment: InstantMessage {
  public var segmentID: InstantID<Segment>
  public var transcriptionID: InstantID<Transcription>
  public var index: Int
  public var words: [String]
  public var isFinal: Bool
  public var wallStart: Date
  public var wallEnd: Date
  public var relativeStartMilliseconds: Int
  public var relativeEndMilliseconds: Int
  public var nextOpenSegmentID: InstantID<Segment>?

  public init(
    segmentID: InstantID<Segment>,
    transcriptionID: InstantID<Transcription>,
    index: Int,
    words: [String],
    isFinal: Bool,
    wallStart: Date,
    wallEnd: Date,
    relativeStartMilliseconds: Int,
    relativeEndMilliseconds: Int,
    nextOpenSegmentID: InstantID<Segment>? = nil
  ) {
    self.segmentID = segmentID
    self.transcriptionID = transcriptionID
    self.index = index
    self.words = words
    self.isFinal = isFinal
    self.wallStart = wallStart
    self.wallEnd = wallEnd
    self.relativeStartMilliseconds = relativeStartMilliseconds
    self.relativeEndMilliseconds = relativeEndMilliseconds
    self.nextOpenSegmentID = nextOpenSegmentID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<SpeechUpserted>
  {
    _ = client
    let text = words.joined(separator: " ")
    let wordsJSON = Segment.encodeWords(words)
    let nextID = nextOpenSegmentID
    return InstantPreparedMessage(
      change: SpeechUpserted(
        segmentID: segmentID,
        isFinal: isFinal,
        nextOpenSegmentID: nextID
      )
    ) {
      Segment.updateExisting(
        id: segmentID,
        Segment.wordsJSON.set(wordsJSON),
        Segment.text.set(text),
        Segment.isFinal.set(isFinal),
        Segment.wallStart.set(wallStart),
        Segment.wallEnd.set(wallEnd),
        Segment.relativeStartMilliseconds.set(relativeStartMilliseconds),
        Segment.relativeEndMilliseconds.set(relativeEndMilliseconds)
      )
      if isFinal, let nextID {
        Segment.create(
          id: nextID,
          Segment.transcription.set(transcriptionID),
          Segment.index.set(index + 1),
          Segment.wallStart.set(wallEnd),
          Segment.wallEnd.set(wallEnd),
          Segment.relativeStartMilliseconds.set(relativeEndMilliseconds),
          Segment.relativeEndMilliseconds.set(relativeEndMilliseconds),
          Segment.bodyKind.set("speech"),
          Segment.wordsJSON.set("[]"),
          Segment.text.set(""),
          Segment.isFinal.set(false)
        )
      }
    }
  }
}

// MARK: - preference

public struct PreferenceSeeded: Hashable, Sendable {}

public struct EnsurePreference: InstantMessage {
  public init() {}

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<PreferenceSeeded>
  {
    _ = client
    return InstantPreparedMessage(change: PreferenceSeeded()) {
      Preference.create(
        id: Preference.singletonID,
        Preference.speechRate.set(1.0),
        Preference.speechRateDefault.set(1.0),
        Preference.debugPanelPresentation.set("expanded")
      )
    }
  }
}

public struct SpeechRateUpdated: Hashable, Sendable {
  public var speechRate: Double
}

public struct SetSpeechRate: InstantMessage {
  public var speechRate: Double

  public init(speechRate: Double) {
    self.speechRate = speechRate
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<SpeechRateUpdated>
  {
    _ = client
    return InstantPreparedMessage(change: SpeechRateUpdated(speechRate: speechRate)) {
      Preference.updateExisting(
        id: Preference.singletonID,
        Preference.speechRate.set(speechRate)
      )
    }
  }
}
