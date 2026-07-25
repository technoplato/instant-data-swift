# Preferences Screen, V3

> Design target: use current `Sources/` declarations and compiling fixtures in
> `Tests/` as the authoritative inventory of usable symbols.

URI: `settings.preferences` (`voicetrail://settings/preferences`)

This screen demonstrates renderable sync state and call-site callbacks
for explicit user actions. `@InstantSyncStatus` exposes state. Buttons
send messages such as refresh, sign out, flush, and clear cache.

This is an intentional exception to the normal-feature boundary: delivery
status and flush are the user-visible purpose of this Preferences section.
Recording, playback, and list features do not coordinate outbox or reconnect.

Implementation status (2026-07-18): commits `4ddf46b`, `ff71165`, and
`7176dfa` compile and test the recorded `@ConnectionStatus`,
`@InstantSyncStatus`, and `@InstantStorageStatus` surface. Sync phases come
from the canonical connection observer; storage sizes come from the real
SQLite/file runtime; manual flush and typed download clearing retain explicit
call-site callbacks. The next boundary is the integrated VoiceTrail app target,
not another syntax-design pass for this screen.

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

struct VoiceTrailPreferencesScreen: View {
  @InstantAuth(
    VoiceTrailUser.self,
    providers: VoiceTrailAuthProviders.self
  )
  private var auth

  @ConnectionStatus
  private var connection

  @InstantSyncStatus
  private var sync

  @InstantStorageStatus
  private var storage

  @LocalID("device")
  private var deviceID

  @Dependency(\.analytics)
  private var analytics

  @Dependency(\.clipboard)
  private var clipboard

  @Dependency(\.haptics)
  private var haptics

  @Dependency(\.toast)
  private var toast

  var body: some View {
    Form {
      accountSection
      syncSection
      storageSection
      developerSection
    }
    .navigationTitle("Preferences")
  }

  private var accountSection:
    some View {
    Section("Account") {
      LabeledContent(
        "Email",
        value: auth.user?.email ?? "Guest"
      )

      LabeledContent(
        "Status",
        value: auth.status.title
      )

      Button {
        refreshSessionButtonTapped()
      } label: {
        Label(
          "Refresh session",
          systemImage: "arrow.clockwise"
        )
      }
      .disabled(auth.isBusy)

      Button(role: .destructive) {
        signOutButtonTapped()
      } label: {
        Label(
          "Sign out",
          systemImage:
            "rectangle.portrait.and.arrow.right"
        )
      }
      .disabled(auth.isBusy)
    }
  }

  private var syncSection:
    some View {
    Section("Sync") {
      Picker(
        "Mode",
        selection: $sync.policy
      ) {
        ForEach(
          InstantSyncPolicy.displayCases
        ) { policy in
          Text(policy.title)
            .tag(policy)
        }
      }

      LabeledContent(
        "Summary",
        value: sync.summary
      )

      LabeledContent(
        "Connection",
        value: connection.state.title
      )

      LabeledContent(
        "Pending writes",
        value:
          sync.pendingOutboxCount
            .formatted()
      )

      LabeledContent(
        "Last remote change",
        value:
          sync.lastRemoteChangeDescription
      )

      Button {
        flushButtonTapped()
      } label: {
        Label(
          "Flush now",
          systemImage:
            "arrow.up.arrow.down.circle"
        )
      }
      .disabled(!sync.canFlush)

      Toggle(
        "Premium-only sync",
        isOn: $sync.usesPremiumGate
      )
    }
  }

  private var storageSection:
    some View {
    Section("Storage") {
      LabeledContent(
        "Local cache",
        value:
          storage.localCacheSize
            .formatted(
              .byteCount(style: .file)
            )
      )

      LabeledContent(
        "Stream cache",
        value:
          storage.streamCacheSize
            .formatted(
              .byteCount(style: .file)
            )
      )

      Button {
        clearDownloadedAudioButtonTapped()
      } label: {
        Label(
          "Clear downloaded audio",
          systemImage: "speaker.slash"
        )
      }
    }
  }

  private var developerSection:
    some View {
    Section("Developer") {
      Button {
        copyDeviceIDButtonTapped()
      } label: {
        Label(
          "Copy device id",
          systemImage: "doc.on.doc"
        )
      }

      NavigationLink {
        OutboxInspectorScreen()
      } label: {
        Label(
          "Inspect outbox",
          systemImage: "tray.full"
        )
      }
    }
  }

  private func refreshSessionButtonTapped() {
    auth.refreshSession(
      onRefreshed: { event in
        analytics.track(
          .sessionRefreshed(
            event.session.userID
          )
        )
        toast.show("Session refreshed")
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func signOutButtonTapped() {
    auth.signOut(
      onSignedOut: { event in
        analytics.track(
          .signedOut(
            event.userID
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

  /// Manual flush is a user action.
  ///
  /// The live `sync` value renders connection and outbox state. These
  /// callbacks only report side effects for this explicit tap.
  private func flushButtonTapped() {
    sync.flush(
      onStarted: { event in
        analytics.track(
          .manualSyncFlushStarted(
            pending: event.pendingCount
          )
        )
      },
      onAccepted: { event in
        toast.show(
          "Synced "
            + event.acceptedMutationCount
              .formatted()
            + " changes"
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func clearDownloadedAudioButtonTapped() {
    storage.clearDownloadedFiles(
      matching: RecordingAudioPath.self,
      onCleared: { event in
        toast.show(
          "Cleared "
            + event.fileCount.formatted()
            + " files"
        )
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
      }
    )
  }

  private func copyDeviceIDButtonTapped() {
    guard let deviceID else {
      toast.show("Device id loading")
      return
    }

    clipboard.copy(deviceID)
    toast.show("Device id copied")
  }
}
```
