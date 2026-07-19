import Foundation

public struct VoiceTrailV3CaptureContract: Hashable, Sendable {
  public var recordingID: String
  public var transcriptionID: String
  public var title: String
  public var ownerUserID: String
  public var deviceID: String
  public var state: String
  public var durationMilliseconds: Int
  public var transcriptionState: String

  public init(
    recordingID: String,
    transcriptionID: String,
    title: String,
    ownerUserID: String,
    deviceID: String,
    state: String,
    durationMilliseconds: Int,
    transcriptionState: String
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.title = title
    self.ownerUserID = ownerUserID
    self.deviceID = deviceID
    self.state = state
    self.durationMilliseconds = durationMilliseconds
    self.transcriptionState = transcriptionState
  }
}

public struct VoiceTrailV3SharingContract: Hashable, Sendable {
  public var shareID: String
  public var membershipID: String
  public var recordingID: String
  public var title: String
  public var ownerUserID: String
  public var memberUserID: String
  public var role: String

  public init(
    shareID: String,
    membershipID: String,
    recordingID: String,
    title: String,
    ownerUserID: String,
    memberUserID: String,
    role: String
  ) {
    self.shareID = shareID
    self.membershipID = membershipID
    self.recordingID = recordingID
    self.title = title
    self.ownerUserID = ownerUserID
    self.memberUserID = memberUserID
    self.role = role
  }
}

public struct VoiceTrailV3PresenceContract: Hashable, Sendable {
  public var userID: String
  public var displayName: String
  public var isPlaying: Bool
  public var offsetSeconds: Double
  public var focusedSegmentID: String

  public init(
    userID: String,
    displayName: String,
    isPlaying: Bool,
    offsetSeconds: Double,
    focusedSegmentID: String
  ) {
    self.userID = userID
    self.displayName = displayName
    self.isPlaying = isPlaying
    self.offsetSeconds = offsetSeconds
    self.focusedSegmentID = focusedSegmentID
  }
}

public struct VoiceTrailV3ReactionContract: Hashable, Sendable {
  public var emoji: String
  public var offsetSeconds: Double

  public init(emoji: String, offsetSeconds: Double) {
    self.emoji = emoji
    self.offsetSeconds = offsetSeconds
  }
}

public struct VoiceTrailV3PlaybackContract: Hashable, Sendable {
  public var roomType: String
  public var roomID: String
  public var swiftPresence: VoiceTrailV3PresenceContract
  public var typeScriptPresence: VoiceTrailV3PresenceContract
  public var swiftReaction: VoiceTrailV3ReactionContract
  public var typeScriptReaction: VoiceTrailV3ReactionContract

  public init(
    roomType: String,
    roomID: String,
    swiftPresence: VoiceTrailV3PresenceContract,
    typeScriptPresence: VoiceTrailV3PresenceContract,
    swiftReaction: VoiceTrailV3ReactionContract,
    typeScriptReaction: VoiceTrailV3ReactionContract
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.swiftPresence = swiftPresence
    self.typeScriptPresence = typeScriptPresence
    self.swiftReaction = swiftReaction
    self.typeScriptReaction = typeScriptReaction
  }
}

public struct VoiceTrailV3DownloadedFileContract: Hashable, Sendable {
  public var name: String
  public var contentType: String
  public var bytes: [UInt8]
  public var shouldClear: Bool

  public init(name: String, contentType: String, bytes: [UInt8], shouldClear: Bool) {
    self.name = name
    self.contentType = contentType
    self.bytes = bytes
    self.shouldClear = shouldClear
  }
}

public struct VoiceTrailV3PreferencesContract: Hashable, Sendable {
  public var streamContent: String
  public var downloadedFiles: [VoiceTrailV3DownloadedFileContract]

  public init(
    streamContent: String,
    downloadedFiles: [VoiceTrailV3DownloadedFileContract]
  ) {
    self.streamContent = streamContent
    self.downloadedFiles = downloadedFiles
  }

  public var streamByteCount: Int { streamContent.utf8.count }
  public var downloadedByteCount: Int { downloadedFiles.reduce(0) { $0 + $1.bytes.count } }
  public var clearedAudioByteCount: Int {
    downloadedFiles.filter(\.shouldClear).reduce(0) { $0 + $1.bytes.count }
  }
  public var remainingFileNames: [String] {
    downloadedFiles.filter { !$0.shouldClear }.map(\.name).sorted()
  }
}

public struct VoiceTrailV3E2EContract: Hashable, Sendable {
  public var tabs: [VoiceTrailAppTab]
  public var swiftUserID: String
  public var typeScriptUserID: String
  public var capture: VoiceTrailV3CaptureContract
  public var sharing: VoiceTrailV3SharingContract
  public var playback: VoiceTrailV3PlaybackContract
  public var preferences: VoiceTrailV3PreferencesContract

  public static func canonical(
    swiftUserID: String,
    typeScriptUserID: String
  ) -> Self {
    let capture = VoiceTrailV3CaptureContract(
      recordingID: "v3-e2e-swift-recording",
      transcriptionID: "v3-e2e-swift-transcription",
      title: "Swift E2E recording",
      ownerUserID: swiftUserID,
      deviceID: "swift-e2e-device",
      state: "recording",
      durationMilliseconds: 0,
      transcriptionState: "processing"
    )
    return Self(
      tabs: [.auth, .recordings, .capture, .playback, .preferences],
      swiftUserID: swiftUserID,
      typeScriptUserID: typeScriptUserID,
      capture: capture,
      sharing: VoiceTrailV3SharingContract(
        shareID: "v3-e2e-share",
        membershipID: "v3-e2e-membership",
        recordingID: "v3-e2e-typescript-recording",
        title: "TypeScript shared recording",
        ownerUserID: typeScriptUserID,
        memberUserID: swiftUserID,
        role: "reader"
      ),
      playback: VoiceTrailV3PlaybackContract(
        roomType: VoiceTrailPlaybackRoom.roomType,
        roomID: capture.recordingID,
        swiftPresence: VoiceTrailV3PresenceContract(
          userID: swiftUserID,
          displayName: "Swift Listener",
          isPlaying: true,
          offsetSeconds: 12.5,
          focusedSegmentID: "segment-swift"
        ),
        typeScriptPresence: VoiceTrailV3PresenceContract(
          userID: typeScriptUserID,
          displayName: "TypeScript Listener",
          isPlaying: false,
          offsetSeconds: 4.25,
          focusedSegmentID: "segment-typescript"
        ),
        swiftReaction: VoiceTrailV3ReactionContract(
          emoji: "swift-wave",
          offsetSeconds: 12.5
        ),
        typeScriptReaction: VoiceTrailV3ReactionContract(
          emoji: "typescript-wave",
          offsetSeconds: 4.25
        )
      ),
      preferences: VoiceTrailV3PreferencesContract(
        streamContent: "hello-stream",
        downloadedFiles: [
          VoiceTrailV3DownloadedFileContract(
            name: "recording.m4a",
            contentType: "audio/mp4",
            bytes: [0, 1, 2, 3],
            shouldClear: true
          ),
          VoiceTrailV3DownloadedFileContract(
            name: "transcript.txt",
            contentType: "text/plain",
            bytes: [4, 5, 6],
            shouldClear: false
          ),
        ]
      )
    )
  }
}
