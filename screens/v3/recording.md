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
        transcriptionID:
          recorder.transcriptionID
      )
    )
    .instantFetch(
      $attachments,
      RecordingAttachment.liveTimeline(
        recordingID:
          recorder.recordingID
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

Decision, 2026-07-18: dynamic timeline queries receive the recorder's current
concrete IDs. An `InstantQuery` is a value whose identity includes those
filters, so `.instantFetch` replaces the observation whenever either ID
changes. A view-root key path such as
`.session(\.recorder.transcriptionID)` cannot express that dependency as a
reusable Swift API without coupling the entity query to this concrete screen.

Bare `@LocalID("device")` owns its SwiftUI lifecycle. The wrapper resolves the
stable canonical local ID once for the view identity and invalidates the view
when the value or renderable status changes. The canonical concurrency and
relaunch guarantee remains covered by
`InstantReactorParityTests.upstreamReactorGetLocalIDAlwaysReturnsSameID`; the
screen lifecycle and rendering proof is
`V3RecordingFixtureTests.localIDResolutionInvalidatesAHostedSwiftUIView`.

Implementation status (2026-07-18):
`V3RecordingActionFixtureTests` compiles the `auth.user` + `@LocalID` + product
preparation + typed `db.send` start path. It proves stale preparation is
cancelled, optimistic and server-accepted callbacks each run once, rejected
creation reports recovery once, retry does not replay action callbacks, and
accepted local state survives runtime relaunch. Finish and attachment actions,
and the canonical ref-shaped owner/member/transcription graph, remain the next
executable slice.
