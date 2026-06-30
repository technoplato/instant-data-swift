# Playback Screen

URI: `recordings.playback` (`voicetrail://recordings/:recordingID/playback`)

ASCII sketch:

```text
+--------------------------------------------------------------------+
| < Recordings                                  [ Share ] [ ... ]     |
| Morning walk                                                       |
| 38:42  Ready  Primary: Whisper remote  Confidence: 0.91            |
|                                                                    |
|  00:12 -----------O-------------------------------------- 38:42     |
|  [ rewind ] [ play ] [ speed 1.25x ] [ transcript ] [ route ]      |
|                                                                    |
|  Speaker 1                                                         |
|  We should revisit pricing before the meeting tomorrow because...  |
|                                                                    |
|  [ screenshot at 09:14 ] [ link: prototype notes ]                 |
|                                                                    |
|  +------------------------------+  Cleanup stream                   |
|  | route synced to playback     |  "Action items: ..."              |
|  +------------------------------+                                    |
+--------------------------------------------------------------------+
```

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

/// Playback is a coordinated view over graph data, storage, permissions, and
/// optional streams.
///
/// The canonical transcript is still ordinary Instant entities. The stream in
/// this screen is for derived cleanup/summary output that can resume chunk by
/// chunk after relaunch.
struct PlaybackScreen: View {
  let recordingID: InstantID<Recording>

  @InstantAuth(VoiceTrailUser.self) private var auth
  @InstantAudioPlayer private var player

  @Dependency(\.defaultInstantSwiftData) private var db
  @Dependency(\.shareSheet) private var shareSheet
  @Dependency(\.toast) private var toast
  @Dependency(\.analytics) private var analytics

  @State private var visibleWindow = MediaTimeRange(start: .zero, duration: .seconds(45))
  @State private var selectedTab: PlaybackTab = .transcript

  /// The playback header uses one typed graph query.
  ///
  /// Includes use generated relation tokens, not string paths. The membership
  /// row is included so the view can derive what the current user may do.
  @FetchOne(
    Recording.playbackHeader(
      id: .value(recordingID),
      viewer: .currentUser
    )
  )
  private var recording: RecordingPlayback?

  /// Segments are windowed by media time.
  ///
  /// The same query shape drives active captions, scrub previews, and the
  /// transcript list. Filtering by non-indexed time fields should be a macro
  /// diagnostic before this ever ships.
  @FetchAll(
    TranscriptionSegment.playbackWindow(
      recording: .value(recordingID),
      transcription: .primary,
      range: .binding(\.visibleWindow)
    ),
    callbacks: .init(
      onRemoteChange: { change in
        guard change.origin != .currentClient else { return }
        toast.show("\(change.authorDisplayName) edited this transcript")
      }
    )
  )
  private var visibleSegments: [TranscriptionSegment]

  /// Attachments share the same media-relative clock as segments.
  ///
  /// Screenshots, copied text, links, and file blobs can render inline without
  /// guessing where they belong.
  @FetchAll(
    RecordingAttachment.playbackWindow(
      recording: .value(recordingID),
      range: .binding(\.visibleWindow)
    )
  )
  private var inlineAttachments: [RecordingAttachment]

  /// Long routes are paged as entities, while the recording keeps a small
  /// route summary for list thumbnails.
  @FetchAll(
    RecordingLocationSample.playbackWindow(
      recording: .value(recordingID),
      range: .binding(\.visibleWindow),
      limit: 500
    )
  )
  private var routeSamples: [RecordingLocationSample]

  /// Streams are useful for progressive derived output.
  ///
  /// A cleanup worker can write chunks to this stream while the user reads
  /// them. If the app relaunches, the reader resumes from the last byte offset.
  @InstantStreamReader(
    TranscriptionCleanupStream.self,
    clientID: .transcriptionCleanup(recordingID),
    resumeFrom: .localCache
  )
  private var cleanupStream: StreamText

  var body: some View {
    Group {
      if let recording {
        content(recording)
      } else {
        ProgressView()
      }
    }
    .task(id: recordingID) {
      await prepareAudioIfAllowed()
    }
  }

  private func content(_ recording: RecordingPlayback) -> some View {
    VStack(spacing: 0) {
      header(recording)
      scrubber(recording)
      tabPicker

      switch selectedTab {
      case .transcript:
        transcript
      case .route:
        RoutePlaybackMap(samples: routeSamples, currentTime: player.currentTime)
      case .cleanup:
        cleanup
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          Task { await shareTranscriptOnly(recording) }
        } label: {
          Label("Share", systemImage: "square.and.arrow.up")
        }

        Menu {
          Button {
            Task { await rename(recording) }
          } label: {
            Label("Rename", systemImage: "pencil")
          }

          if recording.membership.permissions.allows(.downloadAudio) {
            Button {
              Task { await player.downloadAudio() }
            } label: {
              Label("Download audio", systemImage: "arrow.down.circle")
            }
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
      }
    }
  }

  private func header(_ recording: RecordingPlayback) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(recording.recording.title)
        .font(.title2.bold())

      HStack {
        Text(recording.recording.duration.formatted(.voiceTrailDuration))
        Text(recording.recording.state.title)
        Text("Primary: \(recording.primaryTranscription.processorName)")
        Text("Confidence: \(recording.primaryTranscription.confidence.formatted(.percent))")
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }

  private func scrubber(_ recording: RecordingPlayback) -> some View {
    VStack(spacing: 10) {
      Slider(
        value: $player.currentSeconds,
        in: 0...recording.recording.duration.seconds
      )

      HStack {
        Button {
          player.skipBackward(seconds: 10)
        } label: {
          Label("Back", systemImage: "gobackward.10")
        }

        Button {
          player.togglePlayback()
        } label: {
          Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
        }

        Picker("Speed", selection: $player.rate) {
          ForEach(AudioRate.allCases) { rate in
            Text(rate.title).tag(rate)
          }
        }
        .pickerStyle(.menu)
      }
      .buttonStyle(.bordered)
    }
    .padding(.horizontal)
  }

  private var tabPicker: some View {
    Picker("Mode", selection: $selectedTab) {
      ForEach(PlaybackTab.allCases) { tab in
        Text(tab.title).tag(tab)
      }
    }
    .pickerStyle(.segmented)
    .padding()
  }

  private var transcript: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(visibleSegments) { segment in
          SegmentBlock(segment: segment, highlightedTime: player.currentTime)

          ForEach(inlineAttachments.at(offset: segment.endTime)) { attachment in
            AttachmentInlinePreview(attachment: attachment)
          }
        }
      }
      .padding()
    }
  }

  private var cleanup: some View {
    ScrollView {
      Text(cleanupStream.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .overlay(alignment: .bottomTrailing) {
      if cleanupStream.isReading {
        ProgressView()
          .padding()
      }
    }
  }

  /// File access is permission-derived.
  ///
  /// The recording stores an `InstantFile` link. The player asks storage for a
  /// playable URL only if the current role permits listening.
  private func prepareAudioIfAllowed() async {
    guard
      let recording,
      recording.membership.permissions.allows(.listenAudio)
    else {
      return
    }

    await player.prepare(
      file: recording.audioFile,
      permission: .recording(recordingID, capability: .listenAudio)
    )
  }

  private func rename(_ recording: RecordingPlayback) async {
    await db.update(Recording.self, id: recordingID) {
      $0.title = "Edited walk title"
    } onOptimisticCommit: { _ in
      analytics.track(.recordingRenamed(recordingID))
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  /// Public URLs are product entities.
  ///
  /// Transcript-only sharing grants transcript access without implying audio,
  /// route, attachment, or download access.
  private func shareTranscriptOnly(_ recording: RecordingPlayback) async {
    guard recording.membership.permissions.allows(.share) else {
      toast.show("You do not have permission to share this recording.")
      return
    }

    await db.shares.createPublicLink(
      Recording.self,
      id: recordingID,
      scopes: [.viewTranscript],
      expiresAt: .now.addingTimeInterval(24 * 60 * 60)
    ) { share in
      shareSheet.present(share.url)
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }
}

enum PlaybackTab: String, CaseIterable, Identifiable, Sendable {
  case transcript
  case route
  case cleanup

  var id: Self { self }

  var title: String {
    switch self {
    case .transcript: "Transcript"
    case .route: "Route"
    case .cleanup: "Cleanup"
    }
  }
}
```
