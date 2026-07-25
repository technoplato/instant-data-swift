import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI) && os(watchOS)
  import SwiftUI

  @MainActor
  @available(watchOS 10.0, *)
  public struct VoiceTrailWatchRootScreen: View {
    @InstantAuth(VoiceTrailUser.self, providers: VoiceTrailAuthProviders.self)
    private var auth

    @State private var message = "Sign in to see your recordings"
    @FocusState private var focusedField: AuthField?

    private enum AuthField: Hashable {
      case email
      case magicCode
    }

    private let injectedUserID: InstantID<VoiceTrailUser>?
    private let isDemoMode: Bool
    private let usesLocalStoreOnly: Bool

    public init(
      injectedUserID: InstantID<VoiceTrailUser>? = nil,
      isDemoMode: Bool = false,
      usesLocalStoreOnly: Bool = false
    ) {
      self.injectedUserID = injectedUserID
      self.isDemoMode = isDemoMode
      self.usesLocalStoreOnly = usesLocalStoreOnly
    }

    public var body: some View {
      Group {
        if let userID = injectedUserID ?? auth.user?.id {
          VoiceTrailWatchRecordingsScreen(
            userID: userID,
            isDemoMode: isDemoMode,
            usesLocalStoreOnly: usesLocalStoreOnly
          )
        } else {
          signInScreen
        }
      }
      .disabled(auth.isBusy)
      .overlay {
        if auth.isBusy {
          ProgressView()
        }
      }
    }

    private var showsMagicCode: Bool {
      switch auth.mode {
      case .magicCodeSent, .verifyingMagicCode:
        true
      default:
        false
      }
    }

    private var signInScreen: some View {
      NavigationStack {
        List {
          Section {
            Label("VoiceTrail", systemImage: "waveform")
              .font(.headline)
            Text(message)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          Section("Account") {
            TextField("Email", text: $auth.email)
              .textContentType(.emailAddress)
              .focused($focusedField, equals: .email)
              .onSubmit(sendMagicCodeButtonTapped)

            if showsMagicCode {
              TextField("Code", text: $auth.magicCode)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .magicCode)
                .onSubmit(verifyCodeButtonTapped)
              Button("Verify code", action: verifyCodeButtonTapped)
              Button("Different email", action: differentEmailButtonTapped)
            } else {
              Button("Send magic code", action: sendMagicCodeButtonTapped)
            }
          }

          Button("Continue as guest", action: continueAsGuestButtonTapped)
        }
        .navigationTitle("Sign In")
        .defaultFocus($focusedField, .email)
      }
    }

    private func sendMagicCodeButtonTapped() {
      let email = auth.email.trimmingCharacters(in: .whitespacesAndNewlines)
      guard email.contains("@"), email.contains(".") else {
        message = "Enter a valid email."
        focusedField = .email
        return
      }
      auth.sendMagicCode(
        onChallengeSent: { challenge in
          message = "Code sent to \(challenge.email)"
          focusedField = .magicCode
        },
        onFailure: handleAuthFailure
      )
    }

    private func verifyCodeButtonTapped() {
      guard !auth.magicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        message = "Enter the code from your email."
        focusedField = .magicCode
        return
      }
      auth.verifyMagicCode(
        onSignedIn: { _ in message = "Signed in" },
        onFailure: handleAuthFailure
      )
    }

    private func differentEmailButtonTapped() {
      auth.resetMagicCode()
      focusedField = .email
    }

    private func continueAsGuestButtonTapped() {
      auth.signInAsGuest(
        onSignedIn: { _ in message = "Signed in as guest" },
        onFailure: handleAuthFailure
      )
    }

    private func handleAuthFailure(_ error: InstantError) {
      message = error.recoveryMessage
    }
  }

  @MainActor
  @available(watchOS 10.0, *)
  public struct VoiceTrailWatchRecordingsScreen: View {
    @FetchAll(nil) private var recordings: [VoiceTrailRecording]
    @ConnectionStatus private var connection
    @LocalID("device") private var deviceID
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var path: [InstantID<VoiceTrailRecording>] = []
    @State private var message = ""
    @State private var isStarting = false

    private let userID: InstantID<VoiceTrailUser>
    private let isDemoMode: Bool
    private let usesLocalStoreOnly: Bool

    public init(
      userID: InstantID<VoiceTrailUser>,
      isDemoMode: Bool = false,
      usesLocalStoreOnly: Bool = false
    ) {
      self.userID = userID
      self.isDemoMode = isDemoMode
      self.usesLocalStoreOnly = usesLocalStoreOnly
    }

    public var body: some View {
      NavigationStack(path: $path) {
        List {
          Section {
            Button {
              Task { await newRecordingButtonTapped() }
            } label: {
              Label(
                isStarting ? "Starting…" : "New Recording",
                systemImage: "record.circle.fill"
              )
            }
            .tint(.red)
            .disabled(isStarting || deviceID == nil)
            .accessibilityIdentifier("voicetrail-new-recording")
          }

          Section("Recordings") {
            if recordings.isEmpty {
              Text("No recordings yet")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voicetrail-empty-recordings")
            }
            ForEach(recordings) { recording in
              NavigationLink(value: recording.id) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(recording.title)
                    .lineLimit(2)
                  HStack {
                    Text(recording.state.capitalized)
                    Spacer()
                    Text(duration(recording.durationMilliseconds))
                  }
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                }
              }
              .accessibilityIdentifier("voicetrail-recording-\(recording.id.rawValue)")
            }
          }

          Section {
            Label(connectionLabel, systemImage: connectionIcon)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("voicetrail-sync-status")
            if !message.isEmpty {
              Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
        .navigationTitle("VoiceTrail")
        .navigationDestination(for: InstantID<VoiceTrailRecording>.self) { recordingID in
          let recording = recordings.first { $0.id == recordingID }
          VoiceTrailWatchTranscriptScreen(
            recordingID: recordingID,
            title: recording?.title ?? "Recording"
          )
        }
        .task(id: userID) { await observeRecordings() }
        .task { await observeConnection() }
      }
    }

    private var connectionLabel: String {
      switch connection.state {
      case .authenticated: "Synced"
      case .opened: "Connected"
      case .connecting: "Connecting"
      case .closed: isDemoMode ? "On this Watch" : "Offline"
      case .errored: "Sync error"
      }
    }

    private var connectionIcon: String {
      switch connection.state {
      case .authenticated, .opened: "checkmark.icloud"
      case .connecting: "arrow.triangle.2.circlepath.icloud"
      case .closed: isDemoMode ? "applewatch" : "icloud.slash"
      case .errored: "exclamationmark.icloud"
      }
    }

    private func observeRecordings() async {
      do {
        let query =
          usesLocalStoreOnly
          ? VoiceTrailRecording.query.order(VoiceTrailRecording.title)
          : VoiceTrailRecording.recordingsQuery(
            scope: .mine,
            searchText: "",
            viewerID: userID
          )
        try await $recordings.task(query)
      } catch is CancellationError {
      } catch {
        message = String(describing: error)
      }
    }

    private func observeConnection() async {
      do {
        try await $connection.task()
      } catch is CancellationError {
      } catch {
        message = String(describing: error)
      }
    }

    private func newRecordingButtonTapped() async {
      guard let deviceID else { return }
      isStarting = true
      defer { isStarting = false }

      let recordingID = InstantID<VoiceTrailRecording>(
        rawValue: uuid().uuidString.lowercased()
      )
      let transcriptionID = VoiceTrailTranscriptStream.transcriptionID(for: recordingID)

      do {
        let stream = try await db.createStream(
          clientID: VoiceTrailTranscriptStream.clientID(for: recordingID)
        )
        let sendTask = db.send(
          CreateVoiceTrailRecording(
            recordingID: recordingID,
            transcriptionID: transcriptionID,
            ownerID: userID,
            deviceID: deviceID,
            title: "Recording \(now.formatted(date: .omitted, time: .shortened))"
          ),
          onOptimisticCommit: { _ in
            path.append(recordingID)
            message = "Recording started"
          },
          onServerAccepted: { _ in message = "Recording synced" },
          onFailure: handleFailure
        )
        if isDemoMode {
          startDemoTranscript(streamID: stream.id)
        }
        await sendTask.value
      } catch {
        message = String(describing: error)
      }
    }

    private func startDemoTranscript(streamID: String) {
      let client = db
      Task {
        let updates = [
          VoiceTrailTranscriptUpdate(text: "Testing"),
          VoiceTrailTranscriptUpdate(text: "Testing the live"),
          VoiceTrailTranscriptUpdate(text: "Testing the live transcript"),
          VoiceTrailTranscriptUpdate(
            text: "Testing the live transcript on Apple Watch.",
            isFinal: true
          ),
        ]
        for update in updates {
          try? await Task.sleep(for: .milliseconds(700))
          try? await client.appendStreamChunk(streamID: streamID, payload: update.payload)
        }
      }
    }

    private func handleFailure(_ error: InstantError) {
      message = error.recoveryMessage
    }

    private func duration(_ milliseconds: Int) -> String {
      let seconds = milliseconds / 1_000
      return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
  }

  @MainActor
  @available(watchOS 10.0, *)
  public struct VoiceTrailWatchTranscriptScreen: View {
    @StreamChunks private var chunks: [InstantStreamChunk]
    @Dependency(\.defaultInstantSwiftData) private var db

    @State private var streamID: String?
    @State private var message = "Connecting to transcript…"
    @State private var isStopping = false

    private let recordingID: InstantID<VoiceTrailRecording>
    private let title: String

    public init(
      recordingID: InstantID<VoiceTrailRecording>,
      title: String
    ) {
      self.recordingID = recordingID
      self.title = title
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Label("LIVE", systemImage: "waveform.circle.fill")
            .font(.caption.bold())
            .foregroundStyle(.red)

          Text(transcriptText)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("voicetrail-live-transcript")

          if let update = VoiceTrailTranscriptStream.latestUpdate(in: chunks), update.isFinal {
            Label("Latest phrase final", systemImage: "checkmark.circle.fill")
              .font(.caption2)
              .foregroundStyle(.green)
          } else {
            Text(message)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }

          Button(role: .destructive) {
            Task { await stopButtonTapped() }
          } label: {
            Label(isStopping ? "Stopping…" : "Stop", systemImage: "stop.circle.fill")
          }
          .disabled(isStopping || streamID == nil)
          .accessibilityIdentifier("voicetrail-stop-recording")
        }
        .padding(.horizontal, 4)
      }
      .navigationTitle(title)
      .task(id: recordingID) { await observeTranscript() }
    }

    private var transcriptText: String {
      VoiceTrailTranscriptStream.latestUpdate(in: chunks)?.text ?? "Listening…"
    }

    private func observeTranscript() async {
      let clientID = VoiceTrailTranscriptStream.clientID(for: recordingID)
      while !Task.isCancelled {
        do {
          let stream = try await db.streamMetadata(clientID: clientID)
          streamID = stream.id
          message = "Transcript updates appear here as they arrive."
          try await $chunks.task(stream.id)
          return
        } catch is CancellationError {
          return
        } catch {
          message = "Waiting for transcript…"
          try? await Task.sleep(for: .seconds(1))
        }
      }
    }

    private func stopButtonTapped() async {
      guard let streamID else { return }
      isStopping = true
      defer { isStopping = false }
      do {
        _ = try await db.closeStream(streamID: streamID)
        let sendTask = db.send(
          FinishVoiceTrailRecording(
            recordingID: recordingID,
            transcriptionID: VoiceTrailTranscriptStream.transcriptionID(for: recordingID),
            durationMilliseconds: 0
          ),
          onOptimisticCommit: { _ in message = "Recording stopped" },
          onServerAccepted: { _ in message = "Recording saved" },
          onFailure: { error in message = error.recoveryMessage }
        )
        await sendTask.value
      } catch {
        message = String(describing: error)
      }
    }
  }
#endif
