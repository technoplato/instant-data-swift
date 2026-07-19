import Foundation
import InstantSwiftData

public enum VoiceTrailAppTab: String, CaseIterable, Hashable, Identifiable, Sendable {
  case auth
  case recordings
  case capture
  case playback
  case preferences

  public var id: Self { self }

  public var title: String {
    switch self {
    case .auth: "Account"
    case .recordings: "Recordings"
    case .capture: "Record"
    case .playback: "Playback"
    case .preferences: "Preferences"
    }
  }

  public var systemImage: String {
    switch self {
    case .auth: "person.crop.circle"
    case .recordings: "list.bullet"
    case .capture: "record.circle"
    case .playback: "play.circle"
    case .preferences: "gearshape"
    }
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class VoiceTrailAppModel: ObservableObject {
    @Published public var selectedTab: VoiceTrailAppTab
    @Published public private(set) var playbackRecordingID: InstantID<VoiceTrailRecording>

    public init(
      selectedTab: VoiceTrailAppTab = .recordings,
      playbackRecordingID: InstantID<VoiceTrailRecording> = InstantID(
        rawValue: "voicetrail-preview-recording"
      )
    ) {
      self.selectedTab = selectedTab
      self.playbackRecordingID = playbackRecordingID
    }

    public func recordingTapped(_ id: InstantID<VoiceTrailRecording>) {
      playbackRecordingID = id
      selectedTab = .playback
    }
  }
#endif
