import Dependencies
import InstantSwiftData
import SwiftUI

// MARK: - Root

@available(iOS 17.0, macOS 14.0, *)
public struct TranscriptionRootScreen: View {
  @StateObject private var program = TranscriptionProgramModel()
  @FetchAll(Recording.list) private var recordings: [Recording]
  @FetchAll(Preference.query) private var preferences: [Preference]

  public init() {}

  public var body: some View {
    ZStack {
      NavigationStack {
        screenBody
          .navigationTitle(navTitle)
          .toolbar {
            ToolbarItem(placement: .primaryAction) {
              Button {
                program.send(.openSettings)
              } label: {
                Image(systemName: "gearshape")
              }
              .disabled(program.topScreen == .settings)
            }
            if program.stack.count > 1 {
              ToolbarItem(placement: .cancellationAction) {
                Button("Back") { program.send(.goBack) }
              }
            }
          }
      }
      TranscriptionFloatingToolbar(program: program) { id in
        recordings.first(where: { $0.id == id })?.title ?? "Recording"
      }
    }
    .safeAreaInset(edge: .bottom) {
      // Reserve space so list content clears the floating bar.
      Color.clear.frame(height: program.mode.capture == nil && program.mode.playback == nil ? 88 : 72)
    }
  }

  @ViewBuilder
  private var screenBody: some View {
    switch program.topScreen {
    case .library:
      TranscriptionLibraryScreen(recordings: recordings, program: program)
    case .timeline(let id):
      TranscriptionTimelineScreen(recordingID: id, program: program)
    case .settings:
      TranscriptionSettingsScreen(preferences: preferences)
    }
  }

  private var navTitle: String {
    switch program.topScreen {
    case .library: "Recordings"
    case .timeline: "Timeline"
    case .settings: "Settings"
    }
  }
}

// MARK: - Library (SyncUps stopwatch list card feel)

@available(iOS 17.0, macOS 14.0, *)
struct TranscriptionLibraryScreen: View {
  let recordings: [Recording]
  @ObservedObject var program: TranscriptionProgramModel

  var body: some View {
    List {
      if !program.statusMessage.isEmpty {
        Section {
          Text(program.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Section {
        if recordings.isEmpty {
          ContentUnavailableView(
            "No recordings",
            systemImage: "waveform",
            description: Text("Tap the red record button to start. Speech is simulated.")
          )
          .listRowBackground(Color.clear)
        } else {
          ForEach(recordings) { recording in
            recordingCard(recording)
          }
        }
      } header: {
        HStack {
          Text("Recordings")
          Spacer()
          Text("\(recordings.count)")
            .foregroundStyle(.secondary)
        }
      }
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #endif
  }

  private func recordingCard(_ recording: Recording) -> some View {
    let isCapture = program.mode.capture?.recordingID == recording.id
    let isPlayback = program.mode.playback?.recordingID == recording.id
    return HStack(alignment: .center, spacing: 12) {
      Button {
        program.send(.openRecording(recording.id))
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(recording.title)
              .font(.headline)
              .foregroundStyle(.primary)
            if isCapture {
              Circle()
                .fill(program.mode.isRecordingPaused ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            }
          }
          Text(formatDuration(recording))
            .font(.title2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

      Button {
        if isPlayback {
          program.send(
            program.mode.playback?.isPaused == true ? .resumePlayback : .pausePlayback
          )
        } else {
          program.send(.playRecording(recording.id))
        }
      } label: {
        Image(
          systemName: isPlayback && program.mode.playback?.isPaused == false
            ? "pause.fill" : "play.fill"
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(Circle().fill(isPlayback ? Color.orange : Color.green))
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 8)
  }

  private func formatDuration(_ recording: Recording) -> String {
    if program.mode.capture?.recordingID == recording.id {
      return format(program.captureElapsed)
    }
    let ms = recording.durationMilliseconds
    return format(TimeInterval(ms) / 1000)
  }

  private func format(_ value: TimeInterval) -> String {
    let total = max(0, Int(value))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    let frac = Int((value.truncatingRemainder(dividingBy: 1)) * 1000)
    if h > 0 {
      return String(format: "%d:%02d:%02d.%03d", h, m, s, frac)
    }
    return String(format: "%d:%02d.%03d", m, s, frac)
  }
}

// MARK: - Timeline

@available(iOS 17.0, macOS 14.0, *)
struct TranscriptionTimelineScreen: View {
  let recordingID: InstantID<Recording>
  @ObservedObject var program: TranscriptionProgramModel
  @FetchAll(Transcription.query) private var transcriptions: [Transcription]
  @FetchAll(Segment.query) private var allSegments: [Segment]

  var body: some View {
    let transcription = transcriptions.first(where: { $0.recording == recordingID })
    let segments =
      transcription.map { t in
        allSegments.filter { $0.transcription == t.id }.sorted { $0.index < $1.index }
      } ?? []

    List {
      if program.mode.capture?.recordingID == recordingID, !program.liveWords.isEmpty {
        Section("Live") {
          Text(program.liveWords.joined(separator: " "))
            .font(.body)
        }
      }
      Section("Segments") {
        if segments.isEmpty {
          Text("No segments yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(segments) { segment in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("#\(segment.index)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
                if segment.isFinal {
                  Text("final")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
              }
              Text(segment.text.isEmpty ? "(open)" : segment.text)
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
  }
}

// MARK: - Settings

@available(iOS 17.0, macOS 14.0, *)
struct TranscriptionSettingsScreen: View {
  let preferences: [Preference]
  @Dependency(\.defaultInstantSwiftData) private var db

  var body: some View {
    let pref = preferences.first
    Form {
      Section("Speech simulation") {
        if let pref {
          LabeledContent("Rate", value: String(format: "%.1f×", pref.speechRate))
          Slider(
            value: Binding(
              get: { pref.speechRate },
              set: { db.send(SetSpeechRate(speechRate: $0)) }
            ),
            in: 0.5...2.0,
            step: 0.1
          )
        } else {
          Text("Preference row not seeded yet")
            .foregroundStyle(.secondary)
        }
      }
      Section("About") {
        Text("Transcription example — Instant first, simulated speech, dual-track mode.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}
