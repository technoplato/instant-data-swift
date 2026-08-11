import Dependencies
import Foundation
import InstantSwiftData

// MARK: - Program state (ADR 0016: screen stack + nine flat mode leaves)

public struct CaptureHandle: Hashable, Sendable {
  public var recordingID: InstantID<Recording>
  public var transcriptionID: InstantID<Transcription>
  public var openSegmentID: InstantID<Segment>
  public var startedAt: Date
  public var segmentIndex: Int

  public init(
    recordingID: InstantID<Recording>,
    transcriptionID: InstantID<Transcription>,
    openSegmentID: InstantID<Segment>,
    startedAt: Date = .now,
    segmentIndex: Int = 0
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.openSegmentID = openSegmentID
    self.startedAt = startedAt
    self.segmentIndex = segmentIndex
  }
}

public struct PlaybackHandle: Hashable, Sendable {
  public var recordingID: InstantID<Recording>
  public var mediaPosition: TimeInterval
  public var isPaused: Bool

  public init(
    recordingID: InstantID<Recording>,
    mediaPosition: TimeInterval = 0,
    isPaused: Bool = false
  ) {
    self.recordingID = recordingID
    self.mediaPosition = mediaPosition
    self.isPaused = isPaused
  }
}

public enum Screen: Hashable, Sendable {
  case library
  case timeline(InstantID<Recording>)
  case settings
}

/// Flat Cartesian mode (Q17). Hosts may use two phase enums internally.
public enum Mode: Hashable, Sendable {
  case recordingIdlePlaybackIdle
  case recordingIdlePlaybackPlaying(PlaybackHandle)
  case recordingIdlePlaybackPaused(PlaybackHandle)
  case recordingActivePlaybackIdle(CaptureHandle)
  case recordingActivePlaybackPlaying(CaptureHandle, PlaybackHandle)
  case recordingActivePlaybackPaused(CaptureHandle, PlaybackHandle)
  case recordingPausedPlaybackIdle(CaptureHandle)
  case recordingPausedPlaybackPlaying(CaptureHandle, PlaybackHandle)
  case recordingPausedPlaybackPaused(CaptureHandle, PlaybackHandle)

  public var capture: CaptureHandle? {
    switch self {
    case .recordingActivePlaybackIdle(let c),
      .recordingActivePlaybackPlaying(let c, _),
      .recordingActivePlaybackPaused(let c, _),
      .recordingPausedPlaybackIdle(let c),
      .recordingPausedPlaybackPlaying(let c, _),
      .recordingPausedPlaybackPaused(let c, _):
      return c
    default:
      return nil
    }
  }

  public var playback: PlaybackHandle? {
    switch self {
    case .recordingIdlePlaybackPlaying(let p), .recordingIdlePlaybackPaused(let p):
      return p
    case .recordingActivePlaybackPlaying(_, let p), .recordingActivePlaybackPaused(_, let p),
      .recordingPausedPlaybackPlaying(_, let p), .recordingPausedPlaybackPaused(_, let p):
      return p
    default:
      return nil
    }
  }

  public var isRecordingActive: Bool {
    switch self {
    case .recordingActivePlaybackIdle, .recordingActivePlaybackPlaying,
      .recordingActivePlaybackPaused:
      return true
    default:
      return false
    }
  }

  public var isRecordingPaused: Bool {
    switch self {
    case .recordingPausedPlaybackIdle, .recordingPausedPlaybackPlaying,
      .recordingPausedPlaybackPaused:
      return true
    default:
      return false
    }
  }

  public var isPlaybackPlaying: Bool {
    switch self {
    case .recordingIdlePlaybackPlaying, .recordingActivePlaybackPlaying,
      .recordingPausedPlaybackPlaying:
      return true
    default:
      return false
    }
  }
}

public enum Message: Hashable, Sendable {
  case startRecording
  case pauseRecording
  case resumeRecording
  case stopRecording
  case playRecording(InstantID<Recording>)
  case pausePlayback
  case resumePlayback
  case stopPlayback
  case scrubPlayback(TimeInterval)
  case openRecording(InstantID<Recording>)
  case openSettings
  case goBack
  case speechRecognized(words: [String], isFinal: Bool)
}

@MainActor
public final class TranscriptionProgramModel: ObservableObject {
  @Published public private(set) var stack: [Screen] = [.library]
  @Published public private(set) var mode: Mode = .recordingIdlePlaybackIdle
  @Published public private(set) var statusMessage: String = ""
  @Published public var liveWords: [String] = []
  @Published public var captureElapsed: TimeInterval = 0

  @Dependency(\.defaultInstantSwiftData) private var db
  @Dependency(\.uuid) private var uuid
  @Dependency(\.date.now) private var now
  @Dependency(\.continuousClock) private var clock

  private var speechTask: Task<Void, Never>?
  private var tickTask: Task<Void, Never>?
  private var simWordIndex = 0

  private static let sampleWords = [
    "hello", "this", "is", "simulated", "speech", "for", "the", "transcription",
    "example", "instant", "first", "no", "microphone", "required",
  ]

  public init() {}

  public var topScreen: Screen { stack.last ?? .library }

  public func send(_ message: Message) {
    switch message {
    case .startRecording:
      startRecording()
    case .pauseRecording:
      pauseRecording()
    case .resumeRecording:
      resumeRecording()
    case .stopRecording:
      stopRecording()
    case .playRecording(let id):
      playRecording(id)
    case .pausePlayback:
      pausePlayback()
    case .resumePlayback:
      resumePlayback()
    case .stopPlayback:
      stopPlayback()
    case .scrubPlayback(let position):
      scrubPlayback(position)
    case .openRecording(let id):
      push(.timeline(id))
    case .openSettings:
      push(.settings)
    case .goBack:
      goBack()
    case .speechRecognized(let words, let isFinal):
      applySpeech(words: words, isFinal: isFinal)
    }
  }

  private func push(_ screen: Screen) {
    if stack.last == screen { return }
    stack.append(screen)
  }

  private func goBack() {
    guard stack.count > 1 else { return }
    stack.removeLast()
  }

  private func startRecording() {
    let recordingID = InstantID<Recording>(rawValue: uuid().uuidString.lowercased())
    let transcriptionID = InstantID<Transcription>(rawValue: uuid().uuidString.lowercased())
    let segmentID = InstantID<Segment>(rawValue: uuid().uuidString.lowercased())
    let title = "Recording \(Date.now.formatted(date: .abbreviated, time: .shortened))"
    let started = now
    db.send(
      CreateRecording(
        recordingID: recordingID,
        transcriptionID: transcriptionID,
        openSegmentID: segmentID,
        title: title,
        now: started
      ),
      onOptimisticCommit: { [weak self] _ in
        guard let self else { return }
        let capture = CaptureHandle(
          recordingID: recordingID,
          transcriptionID: transcriptionID,
          openSegmentID: segmentID,
          startedAt: started,
          segmentIndex: 0
        )
        self.mode = self.withCapture(capture, recordingActive: true)
        self.liveWords = []
        self.captureElapsed = 0
        self.simWordIndex = 0
        self.startTicks()
        self.startSimSpeech()
        self.push(.timeline(recordingID))
        self.statusMessage = "Recording"
      },
      onFailure: { [weak self] error in
        self?.statusMessage = error.recoveryMessage
      }
    )
  }

  private func pauseRecording() {
    guard let capture = mode.capture, mode.isRecordingActive else { return }
    stopSimSpeech()
    mode = withCapture(capture, recordingActive: false)
    statusMessage = "Paused"
  }

  private func resumeRecording() {
    guard let capture = mode.capture, mode.isRecordingPaused else { return }
    mode = withCapture(capture, recordingActive: true)
    startSimSpeech()
    statusMessage = "Recording"
  }

  private func stopRecording() {
    guard let capture = mode.capture else { return }
    stopSimSpeech()
    stopTicks()
    let durationMs = Int(max(0, now.timeIntervalSince(capture.startedAt)) * 1000)
    db.send(
      FinishRecording(
        recordingID: capture.recordingID,
        transcriptionID: capture.transcriptionID,
        finishedAt: now,
        durationMilliseconds: durationMs
      ),
      onOptimisticCommit: { [weak self] _ in
        guard let self else { return }
        self.mode = self.withoutCapture()
        self.liveWords = []
        self.statusMessage = "Stopped"
      },
      onFailure: { [weak self] error in
        self?.statusMessage = error.recoveryMessage
      }
    )
  }

  private func playRecording(_ id: InstantID<Recording>) {
    let playback = PlaybackHandle(recordingID: id, mediaPosition: 0, isPaused: false)
    mode = withPlayback(playback, playing: true)
    statusMessage = "Playing"
  }

  private func pausePlayback() {
    guard var playback = mode.playback else { return }
    playback.isPaused = true
    mode = withPlayback(playback, playing: false)
  }

  private func resumePlayback() {
    guard var playback = mode.playback else { return }
    playback.isPaused = false
    mode = withPlayback(playback, playing: true)
  }

  private func stopPlayback() {
    mode = withoutPlayback()
  }

  private func scrubPlayback(_ position: TimeInterval) {
    guard var playback = mode.playback else { return }
    playback.mediaPosition = max(0, position)
    mode = withPlayback(playback, playing: !playback.isPaused && mode.isPlaybackPlaying)
  }

  private func applySpeech(words: [String], isFinal: Bool) {
    guard mode.isRecordingActive, var capture = mode.capture else { return }
    liveWords = words
    let wallEnd = now
    let relativeEnd = Int(wallEnd.timeIntervalSince(capture.startedAt) * 1000)
    let nextID: InstantID<Segment>? =
      isFinal ? InstantID(rawValue: uuid().uuidString.lowercased()) : nil
    db.send(
      UpsertSpeechSegment(
        segmentID: capture.openSegmentID,
        transcriptionID: capture.transcriptionID,
        index: capture.segmentIndex,
        words: words,
        isFinal: isFinal,
        wallStart: capture.startedAt,
        wallEnd: wallEnd,
        relativeStartMilliseconds: 0,
        relativeEndMilliseconds: relativeEnd,
        nextOpenSegmentID: nextID
      ),
      onOptimisticCommit: { [weak self] change in
        guard let self else { return }
        if change.isFinal, let next = change.nextOpenSegmentID {
          capture.openSegmentID = next
          capture.segmentIndex += 1
          self.mode = self.withCapture(capture, recordingActive: true)
          self.liveWords = []
        }
      },
      onFailure: { [weak self] error in
        self?.statusMessage = error.recoveryMessage
      }
    )
  }

  // MARK: - Mode algebra helpers

  private func withCapture(_ capture: CaptureHandle, recordingActive: Bool) -> Mode {
    let playback = mode.playback
    switch (recordingActive, playback) {
    case (true, nil):
      return .recordingActivePlaybackIdle(capture)
    case (true, let p?) where !p.isPaused:
      return .recordingActivePlaybackPlaying(capture, p)
    case (true, let p?):
      return .recordingActivePlaybackPaused(capture, p)
    case (false, nil):
      return .recordingPausedPlaybackIdle(capture)
    case (false, let p?) where !p.isPaused:
      return .recordingPausedPlaybackPlaying(capture, p)
    case (false, let p?):
      return .recordingPausedPlaybackPaused(capture, p)
    }
  }

  private func withoutCapture() -> Mode {
    switch mode.playback {
    case nil:
      return .recordingIdlePlaybackIdle
    case let p? where !p.isPaused:
      return .recordingIdlePlaybackPlaying(p)
    case let p?:
      return .recordingIdlePlaybackPaused(p)
    }
  }

  private func withPlayback(_ playback: PlaybackHandle, playing: Bool) -> Mode {
    var p = playback
    p.isPaused = !playing
    if let capture = mode.capture {
      if mode.isRecordingActive {
        return playing
          ? .recordingActivePlaybackPlaying(capture, p)
          : .recordingActivePlaybackPaused(capture, p)
      }
      return playing
        ? .recordingPausedPlaybackPlaying(capture, p)
        : .recordingPausedPlaybackPaused(capture, p)
    }
    return playing ? .recordingIdlePlaybackPlaying(p) : .recordingIdlePlaybackPaused(p)
  }

  private func withoutPlayback() -> Mode {
    if let capture = mode.capture {
      return mode.isRecordingActive
        ? .recordingActivePlaybackIdle(capture)
        : .recordingPausedPlaybackIdle(capture)
    }
    return .recordingIdlePlaybackIdle
  }

  // MARK: - Simulated speech + elapsed tick

  private func startSimSpeech() {
    speechTask?.cancel()
    speechTask = Task { [weak self] in
      guard let self else { return }
      var buffer: [String] = []
      while !Task.isCancelled {
        try? await clock.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, self.mode.isRecordingActive else { continue }
        let word = Self.sampleWords[self.simWordIndex % Self.sampleWords.count]
        self.simWordIndex += 1
        buffer.append(word)
        let isFinal = buffer.count >= 5
        self.send(.speechRecognized(words: buffer, isFinal: isFinal))
        if isFinal { buffer = [] }
      }
    }
  }

  private func stopSimSpeech() {
    speechTask?.cancel()
    speechTask = nil
  }

  private func startTicks() {
    tickTask?.cancel()
    tickTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(50))
        guard let self, let capture = self.mode.capture else { continue }
        self.captureElapsed = Date.now.timeIntervalSince(capture.startedAt)
      }
    }
  }

  private func stopTicks() {
    tickTask?.cancel()
    tickTask = nil
  }
}
