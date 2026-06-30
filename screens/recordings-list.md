# Recordings List Screen

URI: `recordings.index` (`voicetrail://recordings`)

ASCII sketch:

```text
+--------------------------------------------------------------+
| VoiceTrail                                      [ + Record ]  |
| Signed in as aisha@example.com       Sync: online, 2 pending  |
|                                                              |
|  [ Mine ] [ Shared ] [ Processing ] [ Public Links ]          |
|  Search: [ pricing walk                                ]      |
|                                                              |
|  Today                                                       |
|  ----------------------------------------------------------  |
|  Morning walk                          38:42   Ready         |
|  "We should revisit pricing before..."          Audio Route   |
|                                                              |
|  Shared by Mateo                       12:03   Processing    |
|  "The client liked the prototype..."           Transcript     |
|                                                              |
|  Yesterday                                                   |
|  ----------------------------------------------------------  |
|  Research loop                         51:28   Ready         |
|  "Field notes from the park bench..."         Audio Route     |
+--------------------------------------------------------------+
```

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

/// The main recording browser.
///
/// The screen owns UI-only controls such as the selected scope and search text.
/// It does not own auth state, sync state, remote-change state, or cached query
/// results; those belong to Instant Swift Data wrappers.
struct RecordingsListScreen: View {
  @InstantAuth(VoiceTrailUser.self) private var auth
  @InstantSyncStatus private var sync

  @Dependency(\.router) private var router
  @Dependency(\.toast) private var toast
  @Dependency(\.analytics) private var analytics

  @State private var scope: RecordingListScope = .mine
  @State private var searchText = ""

  /// `@FetchAll` subscribes to a typed query and keeps `rows` current.
  ///
  /// The query is local-first: cached rows appear on launch, optimistic writes
  /// insert immediately, and remote changes from other clients reconcile into
  /// the same array. The callbacks are only for side effects.
  @FetchAll(
    Recording.listRows(
      visibleTo: .currentUser,
      scope: .binding(\.scope),
      searchText: .binding(\.searchText)
    ),
    callbacks: .init(
      onRemoteChange: { change in
        guard change.origin != .currentClient else { return }
        toast.show("\(change.authorDisplayName) updated \(change.entity.title)")
      }
    )
  )
  private var rows: [RecordingListRow]

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        syncBanner
        scopePicker
        searchField
        recordingsList
      }
      .navigationTitle("VoiceTrail")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            router.go(.recordingCapture)
          } label: {
            Label("Record", systemImage: "plus.circle.fill")
          }
        }
      }
    }
  }

  /// Sync state is exposed by the library, not derived from random network
  /// booleans in the view.
  private var syncBanner: some View {
    HStack {
      Text(auth.user?.email ?? "Guest")
      Spacer()
      Label(sync.summary, systemImage: sync.systemImage)
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  /// Filtering is a typed enum.
  ///
  /// The query builder can expand each case into indexed fields and role
  /// capability checks. A misspelled filter cannot sneak through as a string.
  private var scopePicker: some View {
    Picker("Scope", selection: $scope) {
      ForEach(RecordingListScope.allCases) { scope in
        Text(scope.title).tag(scope)
      }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
  }

  private var searchField: some View {
    TextField("Search recordings", text: $searchText)
      .textFieldStyle(.roundedBorder)
      .padding()
  }

  private var recordingsList: some View {
    List(rows) { row in
      Button {
        router.go(.recordingPlayback(row.recording.id))
      } label: {
        RecordingRow(row: row)
      }
      .contextMenu {
        Button {
          Task { await rename(row) }
        } label: {
          Label("Rename", systemImage: "pencil")
        }

        if row.membership.permissions.allows(.share) {
          Button {
            router.go(.shareRecording(row.recording.id))
          } label: {
            Label("Share", systemImage: "square.and.arrow.up")
          }
        }
      }
    }
    .overlay {
      if rows.isEmpty {
        ContentUnavailableView("No recordings", systemImage: "waveform")
      }
    }
  }

  /// A simple title edit demonstrates typed mutation paths.
  ///
  /// The row updates optimistically through `@FetchAll`. The callback only
  /// records a one-off event and shows a small confirmation.
  private func rename(_ row: RecordingListRow) async {
    await row.recording.editTitle { draft in
      draft.title = "Edited walk title"
    } onOptimisticCommit: { recording in
      analytics.track(.recordingRenamed(recording.id))
    } onServerAccepted: { _ in
      toast.show("Title saved")
    } onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  }
}

private struct RecordingRow: View {
  var row: RecordingListRow

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(row.recording.title)
          .font(.headline)
        Spacer()
        Text(row.recording.duration.formatted(.voiceTrailDuration))
          .monospacedDigit()
        statusBadge
      }

      Text(row.primaryTranscriptPreview)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)

      HStack(spacing: 12) {
        if row.membership.permissions.allows(.listenAudio) {
          Label("Audio", systemImage: "speaker.wave.2")
        }
        if row.membership.permissions.allows(.viewRoute) {
          Label("Route", systemImage: "map")
        }
        if row.recording.hasPublicLinks {
          Label("Public", systemImage: "link")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }

  /// The displayed permissions are derived from the persisted role.
  ///
  /// We do not store `canListenAudio` or `canViewTranscript` on the membership
  /// row because those values can drift. `permissions` is a computed Swift view
  /// over `role` plus optional overrides.
  private var statusBadge: some View {
    Text(row.recording.state.title)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(.thinMaterial)
      .clipShape(Capsule())
  }
}

enum RecordingListScope: String, CaseIterable, Identifiable, Sendable {
  case mine
  case shared
  case processing
  case publicLinks

  var id: Self { self }

  var title: String {
    switch self {
    case .mine: "Mine"
    case .shared: "Shared"
    case .processing: "Processing"
    case .publicLinks: "Public Links"
    }
  }
}
```
