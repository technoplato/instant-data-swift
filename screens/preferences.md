# Preferences Screen

URI: `settings.preferences` (`voicetrail://settings/preferences`)

ASCII sketch:

```text
+--------------------------------------------------------------+
| Preferences                                                  |
|                                                              |
| Account                                                      |
| aisha@example.com                             Signed in      |
| [ Link Apple ] [ Link Google ] [ Sign out ]                  |
|                                                              |
| Sync                                                         |
| Mode: Automatic                                              |
| Status: online, caught up, 2 local writes pending            |
| [ Flush now ] [ Premium-only sync ]                          |
|                                                              |
| Storage                                                      |
| Local cache: 184 MB        Stream cache: 12 MB               |
| [ Clear downloaded audio ] [ Compact cache ]                 |
|                                                              |
| Developer                                                    |
| [ Export schema ] [ Inspect outbox ] [ Copy device id ]      |
+--------------------------------------------------------------+
```

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

/// App preferences expose library-owned state without making settings the
/// owner of that state.
///
/// Auth session, linked providers, sync policy, pending outbox work, and cache
/// size all come from Instant Swift Data. The screen can trigger actions, but
/// it should not maintain shadow copies of those facts.
struct PreferencesScreen: View {
  @InstantAuth(VoiceTrailUser.self) private var auth
  @InstantSyncStatus private var sync
  @InstantStorageStatus private var storage

  @Dependency(\.defaultInstantSwiftData) private var db
  @Dependency(\.toast) private var toast
  @Dependency(\.analytics) private var analytics
  @Dependency(\.haptics) private var haptics
  @Dependency(\.clipboard) private var clipboard

  var body: some View {
    Form {
      accountSection
      syncSection
      storageSection
      developerSection
    }
    .navigationTitle("Preferences")
  }

  /// Account display is backed by `auth.session` and `auth.user`.
  ///
  /// The session is not copied into `@State`. If the user links a provider,
  /// refreshes, or signs out from another device, this section updates through
  /// the auth observer.
  private var accountSection: some View {
    Section("Account") {
      LabeledContent("Email", value: auth.user?.email ?? "Guest")
      LabeledContent("Status", value: auth.status.title)

      ForEach(AuthLinkProvider.allCases) { provider in
        Button {
          Task { await link(provider) }
        } label: {
          Label(provider.title, systemImage: provider.systemImage)
        }
        .disabled(auth.linkedProviders.contains(provider.providerID))
      }

      Button {
        Task { await refreshSession() }
      } label: {
        Label("Refresh session", systemImage: "arrow.clockwise")
      }

      Button(role: .destructive) {
        Task { await signOut() }
      } label: {
        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
      }
    }
  }

  /// Sync mode is product behavior, not authorization.
  ///
  /// Premium-only sync can save bandwidth and make the product feel right, but
  /// server permissions still decide what data a user may read or write.
  private var syncSection: some View {
    Section("Sync") {
      Picker("Mode", selection: $sync.policy) {
        ForEach(InstantSyncPolicy.displayCases) { policy in
          Text(policy.title).tag(policy)
        }
      }

      LabeledContent("Status", value: sync.summary)
      LabeledContent("Pending writes", value: sync.pendingOutboxCount.formatted())
      LabeledContent("Last remote change", value: sync.lastRemoteChangeDescription)

      Button {
        Task { await flush() }
      } label: {
        Label("Flush now", systemImage: "arrow.up.arrow.down.circle")
      }

      Toggle("Premium-only sync", isOn: $sync.usesPremiumGate)
    }
  }

  private var storageSection: some View {
    Section("Storage") {
      LabeledContent("Local cache", value: storage.localCacheSize.formatted(.byteCount(style: .file)))
      LabeledContent("Stream cache", value: storage.streamCacheSize.formatted(.byteCount(style: .file)))
      LabeledContent("Downloaded audio", value: storage.downloadedAudioSize.formatted(.byteCount(style: .file)))

      Button {
        Task { await clearDownloadedAudio() }
      } label: {
        Label("Clear downloaded audio", systemImage: "speaker.slash")
      }

      Button {
        Task { await compactCache() }
      } label: {
        Label("Compact cache", systemImage: "externaldrive")
      }
    }
  }

  private var developerSection: some View {
    Section("Developer") {
      Button {
        Task { await exportSchema() }
      } label: {
        Label("Export schema", systemImage: "curlybraces")
      }

      NavigationLink {
        OutboxInspectorScreen()
      } label: {
        Label("Inspect outbox", systemImage: "tray.full")
      }

      Button {
        clipboard.copy(db.deviceID.rawValue)
        toast.show("Device id copied")
      } label: {
        Label("Copy device id", systemImage: "doc.on.doc")
      }
    }
  }

  /// Linking is first-class because guest users should be able to upgrade
  /// without losing locally recorded audio, queued writes, memberships, or share
  /// access.
  private func link(_ provider: AuthLinkProvider) async {
    await auth.linkCurrentUser(with: provider.selection) { event in
      analytics.track(.accountLinked(event.userID, provider: provider.rawValue))
      haptics.success()
    } onFailure: { error in
      toast.show(error.recoveryMessage)
      haptics.error()
    }
  }

  private func refreshSession() async {
    await auth.refreshSession {
      toast.show("Session refreshed")
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  private func signOut() async {
    await auth.signOut {
      analytics.track(.signedOut)
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  private func flush() async {
    await db.sync.flush {
      analytics.track(.manualSyncFlushStarted)
    } onServerAccepted: { result in
      toast.show("Synced \(result.acceptedMutationCount) changes")
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  private func clearDownloadedAudio() async {
    await db.storage.clearDownloadedFiles(
      matching: RecordingAudioPath.self
    ) { result in
      toast.show("Cleared \(result.bytesRemoved.formatted(.byteCount(style: .file)))")
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  private func compactCache() async {
    await db.persistence.compact {
      toast.show("Cache compacted")
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }

  /// Swift is the source of truth, so exporting schema should be a normal tool
  /// operation.
  ///
  /// The generated TypeScript can be checked into the Instant project, while
  /// Swift keeps the stricter enum, relation, ID, and permission guarantees.
  private func exportSchema() async {
    await db.schema.exportTypeScript(
      schema: VoiceTrailSchema.self,
      permissions: VoiceTrailPermissions.self,
      sharing: VoiceTrailSharing.self
    ) { artifact in
      clipboard.copy(artifact.summary)
      toast.show("Schema artifact copied")
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }
}

enum AuthLinkProvider: String, CaseIterable, Identifiable, Sendable {
  case apple
  case google
  case github
  case linkedIn
  case clerk
  case firebase
  case enterpriseSSO

  var id: Self { self }

  var providerID: AuthProviderID {
    switch self {
    case .apple: .apple
    case .google: .google
    case .github: .github
    case .linkedIn: .linkedIn
    case .clerk: .clerk
    case .firebase: .firebase
    case .enterpriseSSO: .custom("enterprise-oidc")
    }
  }

  var title: String {
    switch self {
    case .apple: "Link Apple"
    case .google: "Link Google"
    case .github: "Link GitHub"
    case .linkedIn: "Link LinkedIn"
    case .clerk: "Link Clerk"
    case .firebase: "Link Firebase"
    case .enterpriseSSO: "Link Company SSO"
    }
  }

  var systemImage: String {
    switch self {
    case .apple: "apple.logo"
    case .google: "g.circle"
    case .github: "chevron.left.forwardslash.chevron.right"
    case .linkedIn: "person.crop.square"
    case .clerk: "key"
    case .firebase: "flame"
    case .enterpriseSSO: "building.2"
    }
  }

  var selection: AuthProviderSelection {
    switch self {
    case .apple: .apple(clientName: "apple-ios")
    case .google: .google(clientName: "google-ios")
    case .github: .github(clientName: "github-web")
    case .linkedIn: .linkedIn(clientName: "linkedin-web")
    case .clerk: .clerk(clientName: "clerk")
    case .firebase: .firebase(clientName: "firebase")
    case .enterpriseSSO: .authorizationCode(clientName: "enterprise-oidc")
    }
  }
}
```
