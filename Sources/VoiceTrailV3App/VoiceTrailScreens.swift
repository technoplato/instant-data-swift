import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct VoiceTrailRootScreen: View {
    @StateObject private var model: VoiceTrailAppModel

    public init(model: VoiceTrailAppModel = VoiceTrailAppModel()) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      TabView(selection: $model.selectedTab) {
        VoiceTrailAuthLoginScreen()
          .tabItem { Label(VoiceTrailAppTab.auth.title, systemImage: VoiceTrailAppTab.auth.systemImage) }
          .tag(VoiceTrailAppTab.auth)

        VoiceTrailRecordingsListScreen(onOpenRecording: model.recordingTapped)
          .tabItem {
            Label(
              VoiceTrailAppTab.recordings.title,
              systemImage: VoiceTrailAppTab.recordings.systemImage
            )
          }
          .tag(VoiceTrailAppTab.recordings)

        VoiceTrailRecordingScreen()
          .tabItem {
            Label(VoiceTrailAppTab.capture.title, systemImage: VoiceTrailAppTab.capture.systemImage)
          }
          .tag(VoiceTrailAppTab.capture)

        VoiceTrailPlaybackScreen(recordingID: model.playbackRecordingID)
          .tabItem {
            Label(
              VoiceTrailAppTab.playback.title,
              systemImage: VoiceTrailAppTab.playback.systemImage
            )
          }
          .tag(VoiceTrailAppTab.playback)

        VoiceTrailPreferencesScreen()
          .tabItem {
            Label(
              VoiceTrailAppTab.preferences.title,
              systemImage: VoiceTrailAppTab.preferences.systemImage
            )
          }
          .tag(VoiceTrailAppTab.preferences)
      }
    }
  }

  @MainActor
  public struct VoiceTrailAuthLoginScreen: View {
    @InstantAuth(VoiceTrailUser.self, providers: VoiceTrailAuthProviders.self)
    private var auth

    @State private var message = "Signed out"

    public init() {}

    public var body: some View {
      Form {
        Section("VoiceTrail") {
          Text(message)
          TextField("Email", text: $auth.email)
          if showsMagicCode {
            TextField("Code", text: $auth.magicCode)
            Button("Verify code", action: verifyCodeButtonTapped)
            Button("Use a different email", action: auth.resetMagicCode)
          } else {
            Button("Send magic code", action: sendMagicCodeButtonTapped)
          }
          Button("Continue as guest", action: continueAsGuestButtonTapped)
        }

        Section("Providers") {
          ForEach(auth.providers) { provider in
            Button(provider.title) {
              providerButtonTapped(provider)
            }
          }
        }
      }
      .disabled(auth.isBusy)
    }

    private var showsMagicCode: Bool {
      switch auth.mode {
      case .magicCodeSent, .verifyingMagicCode: true
      default: false
      }
    }

    private func sendMagicCodeButtonTapped() {
      auth.sendMagicCode(
        onChallengeSent: { challenge in message = "Code sent to \(challenge.email)" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func verifyCodeButtonTapped() {
      auth.verifyMagicCode(
        onSignedIn: { event in message = "Signed in as \(event.session.userID)" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func continueAsGuestButtonTapped() {
      auth.signInAsGuest(
        onSignedIn: { event in message = "Guest \(event.session.userID)" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func providerButtonTapped(_ provider: AuthProvider) {
      auth.signIn(
        provider,
        onProviderCompleted: { _ in },
        onSignedIn: { event in message = "Signed in as \(event.session.userID)" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct VoiceTrailRecordingsListScreen: View {
    @InstantAuth(VoiceTrailUser.self, providers: VoiceTrailAuthProviders.self)
    private var auth

    @FetchAll private var recordings: [VoiceTrailRecording]
    @State private var searchText = ""
    @State private var scope: VoiceTrailRecordingScope = .mine

    private let onOpenRecording: @MainActor (InstantID<VoiceTrailRecording>) -> Void

    public init(
      onOpenRecording: @escaping @MainActor (InstantID<VoiceTrailRecording>) -> Void
    ) {
      self.onOpenRecording = onOpenRecording
    }

    public var body: some View {
      VStack {
        Picker("Scope", selection: $scope) {
          ForEach(VoiceTrailRecordingScope.allCases) { scope in
            Text(scope.title).tag(scope)
          }
        }

        List {
          if recordings.isEmpty {
            Text("No recordings yet")
          }
          ForEach(recordings) { recording in
            Button {
              onOpenRecording(recording.id)
            } label: {
              VStack(alignment: .leading) {
                Text(recording.title)
                Text(recording.viewerRole?.rawValue ?? recording.state)
                  .font(.caption)
              }
            }
          }
        }
      }
      .searchable(text: $searchText)
      .instantFetch($recordings, recordingsQuery)
    }

    private var recordingsQuery: InstantQuery<VoiceTrailRecording> {
      VoiceTrailRecording.recordingsQuery(
        scope: scope,
        searchText: searchText,
        viewerID: auth.user?.id
      )
    }
  }

  @MainActor
  public struct VoiceTrailRecordingScreen: View {
    @InstantAuth(VoiceTrailUser.self, providers: VoiceTrailAuthProviders.self)
    private var auth

    @LocalID("device") private var deviceID
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var title = "New recording"
    @State private var message = "Ready"
    @State private var activeRecordingID: InstantID<VoiceTrailRecording>?
    @State private var activeTranscriptionID: InstantID<VoiceTrailTranscription>?

    public init() {}

    public var body: some View {
      Form {
        TextField("Title", text: $title)
        LabeledContent("Device", value: deviceID ?? "Resolving")
        Text(message)
        Button("Start recording", action: startRecordingButtonTapped)
          .disabled(auth.user == nil || deviceID == nil)
        Button("Capture screenshot", action: screenshotButtonTapped)
          .disabled(activeRecordingID == nil)
        Button("Copy text attachment", action: copiedTextButtonTapped)
          .disabled(activeRecordingID == nil)
        Button("Stop recording", action: stopRecordingButtonTapped)
          .disabled(activeRecordingID == nil || activeTranscriptionID == nil)
      }
    }

    private func startRecordingButtonTapped() {
      guard let ownerID = auth.user?.id, let deviceID else { return }
      let recordingID = InstantID<VoiceTrailRecording>(rawValue: uuid().uuidString.lowercased())
      let transcriptionID = InstantID<VoiceTrailTranscription>(
        rawValue: uuid().uuidString.lowercased()
      )
      db.send(
        CreateVoiceTrailRecording(
          recordingID: recordingID,
          transcriptionID: transcriptionID,
          ownerID: ownerID,
          deviceID: deviceID,
          title: title
        ),
        onOptimisticCommit: { change in
          activeRecordingID = change.recordingID
          activeTranscriptionID = change.transcriptionID
          message = "Recording \(change.recordingID.rawValue) started"
        },
        onServerAccepted: { _ in message = "Recording synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func screenshotButtonTapped() {
      createAttachment(kind: "screenshot", contents: "capture.png", offsetMilliseconds: 2_500)
    }

    private func copiedTextButtonTapped() {
      createAttachment(kind: "text", contents: "Copied notes", offsetMilliseconds: 3_000)
    }

    private func createAttachment(
      kind: String,
      contents: String,
      offsetMilliseconds: Int
    ) {
      guard let activeRecordingID else { return }
      db.send(
        CreateVoiceTrailAttachment(
          attachmentID: InstantID(rawValue: uuid().uuidString.lowercased()),
          recordingID: activeRecordingID,
          kind: kind,
          contents: contents,
          offsetMilliseconds: offsetMilliseconds
        ),
        onOptimisticCommit: { change in
          message = "Attachment \(change.attachmentID.rawValue) added"
        },
        onServerAccepted: { _ in message = "Attachment synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func stopRecordingButtonTapped() {
      guard let activeRecordingID, let activeTranscriptionID else { return }
      db.send(
        FinishVoiceTrailRecording(
          recordingID: activeRecordingID,
          transcriptionID: activeTranscriptionID,
          durationMilliseconds: 12_750
        ),
        onOptimisticCommit: { change in
          message = "Finished at \(change.durationMilliseconds) ms"
        },
        onServerAccepted: { _ in message = "Finished recording synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct VoiceTrailPlaybackScreen: View {
    public let recordingID: InstantID<VoiceTrailRecording>

    @Room private var room: InstantRoom<VoiceTrailPlaybackRoom>
    @Presence private var listeners: [VoiceTrailPlaybackPresence]
    @Topic(VoiceTrailPlaybackRoom.Topic.reaction)
    private var reactions: InstantTopic<VoiceTrailReaction>

    @State private var message = "Joining"

    public init(recordingID: InstantID<VoiceTrailRecording>) {
      self.recordingID = recordingID
    }

    public var body: some View {
      Form {
        LabeledContent("Room", value: room.id ?? "Joining")
        LabeledContent("Listeners", value: listeners.count.formatted())
        LabeledContent("Reactions", value: reactions.messages.count.formatted())
        Text(message)
        Button("Send 👍", action: reactionButtonTapped)
          .disabled(!room.isJoined)
      }
      .instantRoom(
        $room,
        InstantRoom<VoiceTrailPlaybackRoom>(
          type: "recording.playback",
          id: recordingID.rawValue
        )
      )
      .presence($listeners, in: room, publishing: currentPresence)
      .instantTopic($reactions, in: room)
    }

    private var currentPresence: VoiceTrailPlaybackPresence {
      VoiceTrailPlaybackPresence(
        userID: InstantID(rawValue: "current-user"),
        displayName: "Current listener",
        isPlaying: false,
        offsetSeconds: 0
      )
    }

    private func reactionButtonTapped() {
      reactions.publish(
        VoiceTrailReaction(emoji: "👍", offsetSeconds: 0),
        onPublished: { _ in message = "Reaction sent" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct VoiceTrailPreferencesScreen: View {
    @ConnectionStatus private var connection
    @InstantSyncStatus private var sync
    @InstantStorageStatus private var storage

    @State private var message = ""

    public init() {}

    public var body: some View {
      Form {
        Section("Sync") {
          Picker("Mode", selection: $sync.policy) {
            ForEach(InstantSyncPolicy.displayCases) { policy in
              Text(policy.title).tag(policy)
            }
          }
          LabeledContent("Summary", value: sync.summary)
          LabeledContent("Connection", value: connection.state.rawValue)
          LabeledContent("Pending writes", value: sync.pendingOutboxCount.formatted())
          Button("Flush now", action: flushButtonTapped)
            .disabled(!sync.canFlush)
        }

        Section("Storage") {
          LabeledContent(
            "Local cache",
            value: storage.localCacheSize.formatted(.byteCount(style: .file))
          )
          LabeledContent(
            "Stream cache",
            value: storage.streamCacheSize.formatted(.byteCount(style: .file))
          )
          Button("Clear downloaded audio", action: clearAudioButtonTapped)
        }

        if !message.isEmpty {
          Text(message)
        }
      }
    }

    private func flushButtonTapped() {
      sync.flush(
        onStarted: { event in message = "Flushing \(event.pendingCount) writes" },
        onAccepted: { event in message = "Synced \(event.acceptedMutationCount) writes" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func clearAudioButtonTapped() {
      storage.clearDownloadedFiles(
        matching: VoiceTrailRecordingAudio.self,
        onCleared: { event in message = "Cleared \(event.fileCount) audio files" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }
#endif
