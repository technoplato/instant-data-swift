import InstantSwiftData
import SwiftUI

// MARK: - Floating toolbar
//
// Adapted from toolshed SyncUps stopwatch FloatingStopwatchControls (proxy domain):
// - Idle: small glowing red record button, bottom center (not blue FAB)
// - Recording: frosted capsule bar — label, title, monospaced time, pause / jump / stop
// - Playback: play/pause + stop on the same bar chrome
// Screenshot ground truth: list cards + bottom “Recording …” capsule.

@available(iOS 17.0, macOS 14.0, *)
public struct TranscriptionFloatingToolbar: View {
  @ObservedObject var program: TranscriptionProgramModel
  var recordingTitle: (InstantID<Recording>) -> String

  @Namespace private var morph

  public init(
    program: TranscriptionProgramModel,
    recordingTitle: @escaping (InstantID<Recording>) -> String = { _ in "Recording" }
  ) {
    self.program = program
    self.recordingTitle = recordingTitle
  }

  public var body: some View {
    VStack {
      Spacer(minLength: 0)
      content
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .allowsHitTesting(true)
  }

  @ViewBuilder
  private var content: some View {
    if let capture = program.mode.capture {
      recordingBar(capture: capture)
    } else if let playback = program.mode.playback {
      playbackBar(playback: playback)
    } else {
      idleRecordButton
    }
  }

  // MARK: Idle — glowing red record (toolshed redesign)

  private var idleRecordButton: some View {
    Button {
      program.send(.startRecording)
    } label: {
      ZStack {
        Circle()
          .fill(Color.red.opacity(0.18))
          .frame(width: 72, height: 72)
          .matchedGeometryEffect(id: "toolbarChrome", in: morph)
        Circle()
          .fill(Color.red.opacity(0.28))
          .frame(width: 58, height: 58)
        Circle()
          .fill(
            LinearGradient(
              colors: [Color.red.opacity(0.95), Color.red.opacity(0.75)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: 44, height: 44)
          .shadow(color: .red.opacity(0.55), radius: 10, y: 2)
          .matchedGeometryEffect(id: "toolbarPrimary", in: morph)
        Circle()
          .fill(Color.white)
          .frame(width: 14, height: 14)
          .matchedGeometryEffect(id: "toolbarIcon", in: morph)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Start recording")
    .padding(.bottom, 12)
  }

  // MARK: Recording bar (screenshot capsule)

  private func recordingBar(capture: CaptureHandle) -> some View {
    let paused = program.mode.isRecordingPaused
    let title = recordingTitle(capture.recordingID)
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(paused ? "Paused" : "Recording")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }
        HStack(spacing: 6) {
          Text(formatElapsed(program.captureElapsed))
            .font(.title3.monospacedDigit().weight(.semibold))
          Circle()
            .fill(paused ? Color.orange : Color.green)
            .frame(width: 7, height: 7)
            .opacity(paused ? 1 : pulseOpacity)
        }
      }
      Spacer(minLength: 8)
      toolbarCircleButton(
        systemName: paused ? "play.fill" : "pause.fill",
        tint: .orange
      ) {
        program.send(paused ? .resumeRecording : .pauseRecording)
      }
      .matchedGeometryEffect(id: "toolbarPrimary", in: morph)
      toolbarCircleButton(systemName: "waveform", tint: .secondary.opacity(0.35), disabled: true) {}
      toolbarCircleButton(systemName: "stop.fill", tint: .red.opacity(0.9)) {
        program.send(.stopRecording)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(barBackground)
    .matchedGeometryEffect(id: "toolbarChrome", in: morph)
  }

  // MARK: Playback bar

  private func playbackBar(playback: PlaybackHandle) -> some View {
    let title = recordingTitle(playback.recordingID)
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(playback.isPaused ? "Paused" : "Playing")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }
        Text(formatElapsed(playback.mediaPosition))
          .font(.title3.monospacedDigit().weight(.semibold))
      }
      Spacer(minLength: 8)
      toolbarCircleButton(
        systemName: playback.isPaused ? "play.fill" : "pause.fill",
        tint: .green
      ) {
        program.send(playback.isPaused ? .resumePlayback : .pausePlayback)
      }
      toolbarCircleButton(systemName: "stop.fill", tint: .secondary) {
        program.send(.stopPlayback)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(barBackground)
  }

  private var barBackground: some View {
    Capsule()
      .fill(.ultraThinMaterial)
      .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
      .overlay(
        Capsule()
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )
  }

  private func toolbarCircleButton(
    systemName: String,
    tint: Color,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.body.weight(.semibold))
        .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.white)
        .frame(width: 40, height: 40)
        .background(Circle().fill(disabled ? Color.secondary.opacity(0.15) : tint))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }

  private var pulseOpacity: Double {
    let phase = Int(program.captureElapsed * 2)
    return phase.isMultiple(of: 2) ? 1.0 : 0.35
  }

  private func formatElapsed(_ value: TimeInterval) -> String {
    let total = max(0, Int(value))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    let fraction = Int((value.truncatingRemainder(dividingBy: 1)) * 100)
    if hours > 0 {
      return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, fraction)
    }
    return String(format: "%d:%02d.%02d", minutes, seconds, fraction)
  }
}
