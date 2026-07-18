# Recording Screen, V3

URI: `recordings.capture` (`voicetrail://recordings/new`)

This screen keeps product recording behavior outside Instant core. The
Instant-facing pieces are local IDs, live queries, and typed mutations.

The recording wrapper owns microphone state. The Instant client owns
mutation delivery. User actions call synchronous message methods, and
callbacks stay next to the action that caused them.

```swift
import SwiftUI
import CoreLocation
import Dependencies
import InstantSwiftData

struct VoiceTrailRecordingScreen: View {
  @InstantAuth(
    VoiceTrailUser.self,
    providers: VoiceTrailAuthProviders.self
  )
  private var auth

  @LocalID("device")
  private var deviceID

  /// Product code, not an Instant primitive.
  ///
  /// This wrapper can compose audio capture, speech recognition, local
  /// files, and location. It should not be required by apps that only
  /// want Instant's query and mutation primitives.
  @VoiceTrailRecordingSession
  private var recorder

  /// Mutations go through the Instant client.
  ///
  /// The screen does not create `Task`; `db.send` starts the async work
  /// and reports user-action callbacks for this call site.
  @Dependency(\.defaultInstantSwiftData)
  private var db

  @Dependency(\.analytics)
  private var analytics

  @Dependency(\.haptics)
  private var haptics

  @Dependency(\.toast)
  private var toast

  @FetchAll
  private var segments:
    [TranscriptionSegment]

  @FetchAll
  private var attachments:
    [RecordingAttachment]

  var body: some View {
    VStack(spacing: 0) {
      header
      waveform
      transcriptTimeline
      controls
    }
    .navigationTitle(recorder.title)
    .instantFetch(
      $segments,
      TranscriptionSegment.liveTimeline(
        transcription:
          .session(
            \.recorder.transcriptionID
          )
      )
    )
    .instantFetch(
      $attachments,
      RecordingAttachment.liveTimeline(
        recording:
          .session(
            \.recorder.recordingID
          )
      )
    )
    .onAppear {
      appeared()
    }
    .onDisappear {
      recorder.keepRecordingInBackground()
    }
  }

  private var header:
    some View {
    HStack {
      VStack(alignment: .leading) {
        TextField(
          "Title",
          text: $recorder.title
        )
        .font(.title2.bold())

        Text(
          recorder.elapsed
            .formatted(
              .voiceTrailDuration
            )
        )
        .monospacedDigit()
        .foregroundStyle(.secondary)
      }

      Spacer()

      Label(
        "REC",
        systemImage: "record.circle.fill"
      )
      .foregroundStyle(.red)
    }
    .padding()
  }

  private var waveform:
    some View {
    VoiceTrailWaveform(
      samples: recorder.audioLevels
    )
    .frame(height: 96)
    .padding(.horizontal)
  }

  private var transcriptTimeline:
    some View {
    ScrollView {
      LazyVStack(
        alignment: .leading,
        spacing: 14
      ) {
        ForEach(segments) { segment in
          SegmentBlock(segment: segment)

          ForEach(
            attachments.at(
              offset: segment.endTime
            )
          ) { attachment in
            AttachmentInlinePreview(
              attachment: attachment
            )
          }
        }
      }
      .padding()
    }
  }

  private var controls:
    some View {
    HStack {
      Button {
        screenshotButtonTapped()
      } label: {
        Label(
          "Screenshot",
          systemImage: "camera.viewfinder"
        )
      }

      Button {
        copiedTextButtonTapped()
      } label: {
        Label(
          "Copy Text",
          systemImage: "doc.on.clipboard"
        )
      }

      Spacer()

      Button(role: .destructive) {
        stopButtonTapped()
      } label: {
        Label(
          "Stop",
          systemImage: "stop.circle.fill"
        )
      }
    }
    .buttonStyle(.bordered)
    .padding()
  }

  /// Starting recording is a screen action with two phases.
  ///
  /// The product recorder prepares local capture. When that succeeds,
  /// Instant receives a typed mutation. The callbacks belong here
  /// because analytics and haptics are specific to this start attempt.
  private func appeared() {
    guard
      recorder.state == .idle,
      let user = auth.user,
      let deviceID
    else {
      return
    }

    recorder.start(
      owner: user.id,
      deviceID: deviceID,
      onPrepared: { prepared in
        createRecordingSession(prepared)
      },
      onStableSegment: { segment in
        analytics.track(
          .stableSegmentReceived(
            segment.segmentID
          )
        )
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func createRecordingSession(
    _ prepared: PreparedRecording
  ) {
    db.send(
      CreateRecordingSession(
        prepared: prepared,
        title: recorder.title
      ),
      onOptimisticCommit: {
        (
          change:
            borrowing RecordingSessionCreatedChange
        ) in
        analytics.track(
          .recordingStarted(
            change.recordingID
          )
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func screenshotButtonTapped() {
    recorder.captureScreenshot(
      onCaptured: { screenshot in
        db.send(
          CreateRecordingAttachment(
            recordingID: recorder.recordingID,
            screenshot: screenshot,
            offset: recorder.elapsed
          ),
          onOptimisticCommit: {
            (
              change:
                borrowing RecordingAttachmentCreatedChange
            ) in
            analytics.track(
              .recordingAttachmentCreated(
                change.attachmentID,
                kind: .screenshot
              )
            )
            haptics.success()
          },
          onFailure: { error in
            toast.show(error.recoveryMessage)
            haptics.error()
          }
        )
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
      }
    )
  }

  private func copiedTextButtonTapped() {
    recorder.readClipboardText(
      onRead: { text in
        db.send(
          CreateRecordingAttachment(
            recordingID: recorder.recordingID,
            text: text,
            offset: recorder.elapsed
          ),
          onOptimisticCommit: {
            (
              change:
                borrowing RecordingAttachmentCreatedChange
            ) in
            analytics.track(
              .recordingAttachmentCreated(
                change.attachmentID,
                kind: .text
              )
            )
            haptics.success()
          },
          onFailure: { error in
            toast.show(error.recoveryMessage)
            haptics.error()
          }
        )
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
      }
    )
  }

  private func stopButtonTapped() {
    recorder.stop(
      onFinished: { finished in
        db.send(
          FinishRecording(
            recordingID: recorder.recordingID,
            transcriptionID:
              recorder.transcriptionID,
            finished: finished
          ),
          onOptimisticCommit: {
            (
              change:
                borrowing RecordingFinishedChange
            ) in
            analytics.track(
              .recordingFinished(
                change.recordingID,
                duration: change.duration
              )
            )
            haptics.success()
          },
          onFailure: { error in
            toast.show(error.recoveryMessage)
            haptics.error()
          }
        )
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
      }
    )
  }
}
```

`@VoiceTrailRecordingSession` is intentionally not an Instant core
wrapper. It is product code composed from audio capture, local IDs,
storage upload, typed mutations, and live queries.
