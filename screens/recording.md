# Recording Screen

URI: `recordings.capture` (`voicetrail://recordings/new`)

ASCII sketch:

```text
+----------------------------------------------------------------+
| < Recordings                                      00:18:42  REC |
|                                                                |
|  Morning walk                                                  |
|  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  |
|                                                                |
|  Speaker 1                                                     |
|  We should revisit pricing before the meeting tomorrow...      |
|                                                                |
|  Attachments at 00:09:14                                       |
|  [ screenshot ]  [ copied quote ]  [ product link ]            |
|                                                                |
|  Route                                                         |
|  +------------------------------+                              |
|  | line over neighborhood map   |                              |
|  +------------------------------+                              |
|                                                                |
|  [ Screenshot ] [ Copy Text ] [ Add Link ] [ Stop ]            |
+----------------------------------------------------------------+
```

```swift
import SwiftUI
import CoreLocation
import Dependencies
import InstantSwiftData

/// Active recording is the place where local-first data matters most.
///
/// Audio capture, route samples, transcript segments, and attachments should
/// all survive airplane mode. Instant Swift Data gives each of those writes a
/// local optimistic commit and queues server work for later.
struct RecordingScreen: View {
  @InstantAuth(VoiceTrailUser.self) private var auth
  @InstantRecordingSession(VoiceTrailRecorder.self) private var recorder

  @Dependency(\.defaultInstantSwiftData) private var db
  @Dependency(\.router) private var router
  @Dependency(\.toast) private var toast
  @Dependency(\.analytics) private var analytics
  @Dependency(\.haptics) private var haptics

  /// Segments are durable rows, not stream chunks.
  ///
  /// The speech engine writes each stable segment as it arrives. The screen can
  /// render local segments immediately, and collaborators can receive the same
  /// rows in realtime when sync is available.
  @FetchAll(
    TranscriptionSegment.liveTimeline(
      transcription: .session(\.recorder.transcriptionID)
    ),
    callbacks: .init(
      onRemoteChange: { change in
        guard change.origin != .currentClient else { return }
        analytics.track(.remoteTranscriptEdit(change.entity.id))
      }
    )
  )
  private var segments: [TranscriptionSegment]

  /// Inline attachments are fetched by the same media-relative time base as
  /// transcript segments.
  ///
  /// This lets screenshots, links, and copied text appear exactly where they
  /// happened during the original recording.
  @FetchAll(
    RecordingAttachment.liveTimeline(
      recording: .session(\.recorder.recordingID)
    )
  )
  private var attachments: [RecordingAttachment]

  /// Route samples are separate entities because a walk can contain thousands
  /// of points.
  ///
  /// The map can render recent points while older points page in, and stopping
  /// the recording does not require rewriting one giant route blob.
  @FetchAll(
    RecordingLocationSample.liveRoute(
      recording: .session(\.recorder.recordingID),
      window: .latest(minutes: 20)
    )
  )
  private var routeSamples: [RecordingLocationSample]

  var body: some View {
    VStack(spacing: 0) {
      header
      waveform
      transcriptTimeline
      routePreview
      controls
    }
    .navigationTitle(recorder.title)
    .task {
      await startIfNeeded()
    }
    .onDisappear {
      recorder.keepRecordingInBackgroundIfNeeded()
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading) {
        TextField("Title", text: $recorder.title)
          .font(.title2.bold())
        Text(recorder.elapsed.formatted(.voiceTrailDuration))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Spacer()
      Label("REC", systemImage: "record.circle.fill")
        .foregroundStyle(.red)
    }
    .padding()
  }

  private var waveform: some View {
    VoiceTrailWaveform(samples: recorder.audioLevels)
      .frame(height: 96)
      .padding(.horizontal)
  }

  private var transcriptTimeline: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(segments) { segment in
            SegmentBlock(segment: segment)
              .id(segment.id)

            ForEach(attachments.at(offset: segment.endTime)) { attachment in
              AttachmentInlinePreview(attachment: attachment)
            }
          }
        }
        .padding()
      }
      .onChange(of: segments.last?.id) { _, id in
        guard let id else { return }
        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
      }
    }
  }

  private var routePreview: some View {
    RoutePreview(samples: routeSamples)
      .frame(height: 140)
      .padding(.horizontal)
  }

  private var controls: some View {
    HStack {
      Button {
        Task { await captureScreenshot() }
      } label: {
        Label("Screenshot", systemImage: "camera.viewfinder")
      }

      Button {
        Task { await captureClipboardText() }
      } label: {
        Label("Copy Text", systemImage: "doc.on.clipboard")
      }

      Button {
        Task { await attachLink() }
      } label: {
        Label("Add Link", systemImage: "link")
      }

      Spacer()

      Button(role: .destructive) {
        Task { await stopRecording() }
      } label: {
        Label("Stop", systemImage: "stop.circle.fill")
      }
    }
    .buttonStyle(.bordered)
    .padding()
  }

  /// Create recording, owner membership, audio upload, and primary
  /// transcription before the first segment arrives.
  ///
  /// This avoids the "persist final transcription" trap. By the time the user
  /// taps Stop, the transcript already exists as rows and JSON word arrays.
  private func startIfNeeded() async {
    guard recorder.state == .idle, let userID = auth.session?.userID else { return }

    await recorder.start(owner: userID) { prepared in
      await db.transact {
        Recording.create(
          id: prepared.recordingID,
          Recording.owner.set(userID),
          Recording.audioFile.set(prepared.audio.fileID),
          Recording.startedAt.set(prepared.startedAt),
          Recording.endedAt.set(nil),
          Recording.state.set(.recording),
          Recording.title.set(recorder.title),
          Recording.titleSource.set(.user),
          Recording.duration.set(.zero),
          Recording.routeSummary.set(nil),
          Recording.sourceDeviceID.set(prepared.deviceID),
          Recording.hasPublicLinks.set(false)
        )

        RecordingMember.create(
          id: .init(),
          RecordingMember.recording.set(prepared.recordingID),
          RecordingMember.user.set(userID),
          RecordingMember.role.set(.owner),
          RecordingMember.overrides.set(nil),
          RecordingMember.acceptedAt.set(.now),
          RecordingMember.expiresAt.set(nil)
        )

        Transcription.create(
          id: prepared.transcriptionID,
          Transcription.recording.set(prepared.recordingID),
          Transcription.processor.set(prepared.processorID),
          Transcription.createdAt.set(.now),
          Transcription.status.set(.processing),
          Transcription.languageCode.set(recorder.languageCode),
          Transcription.text.set(""),
          Transcription.words.set([]),
          Transcription.confidence.set(0),
          Transcription.isPrimary.set(true)
        )
      } onOptimisticCommit: { _ in
        haptics.success()
      } onFailure: { error in
        toast.show(error.recoveryMessage)
      }
    } onStableSegment: { partial in
      await write(partial)
    } onLocation: { sample in
      await write(sample)
    }
  }

  /// Stable recognizer output is merged into ordinary entities.
  ///
  /// Word-level timing is duplicated on the segment and the transcription
  /// because both shapes make different screens simple. The duplication is
  /// intentional domain modeling, not a sync workaround.
  private func write(_ partial: RecognizedSegment) async {
    await db.mutate {
      TranscriptionSegment.upsert(
        id: partial.segmentID,
        TranscriptionSegment.transcription.set(recorder.transcriptionID),
        TranscriptionSegment.startTime.set(partial.startTime),
        TranscriptionSegment.endTime.set(partial.endTime),
        TranscriptionSegment.text.set(partial.text),
        TranscriptionSegment.words.set(partial.words),
        TranscriptionSegment.speakerLabel.set(partial.speakerLabel),
        TranscriptionSegment.speaker.set(partial.speakerID),
        TranscriptionSegment.confidence.set(partial.confidence)
      )

      Transcription.merge(
        id: recorder.transcriptionID,
        Transcription.text.set(partial.fullTranscriptSoFar),
        Transcription.words.set(partial.allWordsSoFar),
        Transcription.confidence.set(partial.runningConfidence)
      )
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  private func write(_ sample: CLLocation) async {
    await db.create(
      RecordingLocationSample.Draft(
        recording: recorder.recordingID,
        capturedAt: sample.timestamp,
        offset: recorder.elapsed,
        latitude: sample.coordinate.latitude,
        longitude: sample.coordinate.longitude,
        altitude: sample.altitude,
        horizontalAccuracy: sample.horizontalAccuracy,
        verticalAccuracy: sample.verticalAccuracy,
        speed: sample.speed,
        course: sample.course,
        source: .coreLocation
      )
    )
  }

  private func captureScreenshot() async {
    guard let screenshotURL = await recorder.captureScreen() else { return }

    await db.storage.upload(
      screenshotURL,
      path: .recordingAttachment(recorder.recordingID, filename: screenshotURL.lastPathComponent)
    ) { file in
      await db.create(
        RecordingAttachment.Draft(
          recording: recorder.recordingID,
          segment: segments.segmentID(containing: recorder.elapsed),
          kind: .screenshot,
          capturedAtOffset: recorder.elapsed,
          capturedAt: .now,
          file: file.id,
          url: nil,
          copiedText: nil,
          title: "Screenshot",
          note: nil
        )
      )
    } onProgress: { progress in
      recorder.attachmentProgress = progress.fractionCompleted
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  private func captureClipboardText() async {
    guard let copiedText = await recorder.readClipboardText() else { return }

    await db.create(
      RecordingAttachment.Draft(
        recording: recorder.recordingID,
        segment: segments.segmentID(containing: recorder.elapsed),
        kind: .copiedText,
        capturedAtOffset: recorder.elapsed,
        capturedAt: .now,
        file: nil,
        url: nil,
        copiedText: copiedText,
        title: "Copied text",
        note: nil
      )
    )
  }

  private func attachLink() async {
    guard let link = await recorder.promptForLink() else { return }

    await db.create(
      RecordingAttachment.Draft(
        recording: recorder.recordingID,
        segment: segments.segmentID(containing: recorder.elapsed),
        kind: .link,
        capturedAtOffset: recorder.elapsed,
        capturedAt: .now,
        file: nil,
        url: link.absoluteString,
        copiedText: nil,
        title: link.host(),
        note: nil
      )
    )
  }

  /// Stop is a status transition over existing data.
  ///
  /// We update `Recording` and `Transcription` metadata, then let the recorder
  /// finish the audio file upload. We do not rewrite every segment at the end.
  private func stopRecording() async {
    let finished = await recorder.stop()

    await db.mutate {
      Recording.updateExisting(
        id: recorder.recordingID,
        Recording.endedAt.set(finished.endedAt),
        Recording.state.set(.ready),
        Recording.duration.set(finished.duration),
        Recording.routeSummary.set(finished.routeSummary)
      )

      Transcription.updateExisting(
        id: recorder.transcriptionID,
        Transcription.status.set(.ready),
        Transcription.confidence.set(finished.confidence)
      )
    } onOptimisticCommit: { _ in
      router.go(.recordingPlayback(recorder.recordingID))
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }
}
```
