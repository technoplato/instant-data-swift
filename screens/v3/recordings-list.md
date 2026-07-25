# Recordings List Screen, V3

> Design target: use current `Sources/` declarations and compiling fixtures in
> `Tests/` as the authoritative inventory of usable symbols. Builder spellings
> shown below may be aspirational unless confirmed in source.

URI: `recordings.index` (`voicetrail://recordings`)

SQLiteData's default shape is direct observation. Use a request object
only when one wrapper needs a composite value.

Prior art:

- `Fetching.md:8-11`
  chooses a wrapper by result shape: collection, single value, or
  bundled reads.
- `Fetching.md:37-41`
  shows a normal list as `@FetchAll var reminders`.
- `Fetching.md:180-199`
  explains that separate wrappers are fine, but own separate
  observations.
- `Fetching.md:201-239`
  introduces request objects only for one composite value.
- `DynamicQueries.md:46-48`
  shows that changing search or filter input reloads the wrapper key.
- `DynamicQuery.swift:17,82-99`
  shows `Facts`, a request used because the view needs rows plus counts.

Paths:

- `upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/`
  `Articles/Fetching.md`
- `upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/`
  `Articles/DynamicQueries.md`
- `upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift`

The recording list should start with the direct shape. It has rows, so
it uses `@FetchAll`.

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

struct VoiceTrailRecordingsListScreen: View {
  /// `@FetchAll` owns list state.
  ///
  /// The screen reads `rows`, while the wrapper handles local cache,
  /// loading, live updates, errors, and replacement when the query
  /// changes.
  @FetchAll
  private var rows:
    [RecordingListRow]

  /// Mutations still go through the Instant client.
  ///
  /// A command is just a typed mutation value. It is not a state owner
  /// and it is not a global command bus.
  @Dependency(\.defaultInstantSwiftData)
  private var db

  @Dependency(\.router)
  private var router

  @Dependency(\.analytics)
  private var analytics

  @Dependency(\.haptics)
  private var haptics

  @Dependency(\.toast)
  private var toast

  @State
  private var scope:
    RecordingListScope = .mine

  @State
  private var searchText = ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        scopePicker
        recordings
      }
      .searchable(text: $searchText)
      .navigationTitle("VoiceTrail")
      .toolbar {
        ToolbarItem(
          placement: .primaryAction
        ) {
          Button {
            router.go(.recordingCapture)
          } label: {
            Label(
              "Record",
              systemImage: "plus.circle.fill"
            )
          }
        }
      }
      .instantFetch(
        $rows,
        rowsQuery
      )
    }
  }

  private var rowsQuery:
    InstantQuery<RecordingListRow> {
    Recording.listRows(
      viewer: .currentUser,
      scope: scope,
      searchText: searchText
    )
  }

  private var scopePicker:
    some View {
    Picker(
      "Scope",
      selection: $scope
    ) {
      ForEach(
        RecordingListScope.allCases
      ) { scope in
        Text(scope.title)
          .tag(scope)
      }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
  }

  private var recordings:
    some View {
    List(rows) { row in
      Button {
        router.go(
          .recordingPlayback(
            row.recording.id
          )
        )
      } label: {
        RecordingRow(row: row)
      }
      .contextMenu {
        Button {
          renameButtonTapped(row)
        } label: {
          Label(
            "Rename",
            systemImage: "pencil"
          )
        }
      }
    }
    .overlay {
      if rows.isEmpty {
        ContentUnavailableView(
          "No recordings",
          systemImage: "waveform"
        )
      }
    }
  }

  private func renameButtonTapped(
    _ row: RecordingListRow
  ) {
    db.send(
      RenameRecording(
        id: row.recording.id,
        title: "Edited walk title"
      ),
      onOptimisticCommit: {
        (
          change:
            borrowing RecordingRenamedChange
        ) in
        let summary = change.summary()

        analytics.track(
          .recordingRenamed(
            summary.id,
            title: summary.newTitle
          )
        )

        haptics.success()
      },
      onServerAccepted: { _ in
        toast.show("Title saved")
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
      }
    )
  }
}
```

Implementation status, 2026-07-18: this direct-wrapper syntax compiles against
the public package in
`Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift`. The modifier
keys replacement by `InstantQuery` identity and delegates lifecycle ownership to
the projected `FetchAll` value. The same fixture proves the rename action's
optimistic and accepted callbacks once, server failure once, retry without
callback replay, and passive refresh without action-callback replay. Callback
parameters borrow the change; the current generic envelope remains Copyable due
to the Swift 6.2 associated-type limitation recorded in the V3 design document.
The data-contract packet is complete. The fixture and credentialed live gate
now use `v3_capture_recordings` with canonical owner/readers/writers links,
the recording-root share, and a viewer-filtered membership projection. The
gate proves owner, reader, reader-to-writer replacement, revocation-to-empty,
and wrapper cancellation without changing this public screen syntax. See
`validation/verify-voice-trail-recordings-list-live.sh` and the clean evidence
at `/tmp/instant-data-swift-voice-trail-recordings-20260718T234408Z/evidence.json`.

The list intentionally has no synchronization coordinator, outbox state, or
manual flush. `@FetchAll` emits local cached and optimistic rows and owns live
replacement. Delivery details remain in the library; explicit user-visible
status belongs in Preferences or diagnostics.

## Composite Request Variant

A request is justified when the wrapper should vend one composite value.
This mirrors SQLiteData's `Facts` example: rows plus counts travel
together, so the view reads one value. The compiling API today is
`InstantFetchKeyRequest` plus `InstantFetchRequest<Value>`; the request is
`Sendable` and is not inherently `Hashable`.

```swift
import SwiftUI
import InstantSwiftData

struct RecordingListSummary: Sendable, Equatable {
  var rows: [VoiceTrailRecording] = []
  var visibleCount = 0
}

struct RecordingListSummaryRequest: InstantFetchKeyRequest {
  var rowsQuery: InstantEntityQuery<VoiceTrailRecording>
  var countQuery: InstantEntityQuery<VoiceTrailRecording>

  var fetchRequest: InstantFetchRequest<RecordingListSummary> {
    InstantFetchRequest(rowsQuery, countQuery) { rows, countedRows in
      RecordingListSummary(
        rows: rows,
        visibleCount: countedRows.count
      )
    }
  }
}

struct VoiceTrailRecordingsSummaryScreen: View {
  @Fetch(
    RecordingListSummaryRequest(
      rowsQuery: VoiceTrailRecording.query.order(
        VoiceTrailRecording.title
      ),
      countQuery: VoiceTrailRecording.query
    )
  )
  private var summary = RecordingListSummary()

  var body: some View {
    List(summary.rows) { recording in
      Text(recording.title)
    }
    .safeAreaInset(edge: .bottom) {
      Text(
        summary.visibleCount.formatted()
          + " recordings"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }
}
```

The static declaration observes automatically and the library owns the child
subscriptions and merged emissions. The current package does not expose a
general composite `.instantFetch` view modifier. If inputs must change during a
single view identity, use a replacement operation that exists in the current
`Fetch` source rather than copying an aspirational builder spelling.

## Row Projection

A row projection is not an entity. The list needs a recording, the
current viewer's membership, and a transcript preview. Decoding that
shape into `Recording` would hide which fields and links were fetched.

The following builder is a design target. Confirm the current implementation
before using `@InstantProjectionBuilder`, `Project`, `Root`, or `Include`.

```swift
import InstantSwiftData

struct RecordingListRow:
  Identifiable,
  Sendable,
  Equatable {
  var recording: Recording
  var membership: RecordingMember
  var primaryTranscript:
    Transcription?
  var preview:
    TranscriptPreview

  var id:
    InstantID<Recording> {
    recording.id
  }

  @InstantProjectionBuilder
  static var projection:
    some InstantProjection<Self> {
    Project(Self.init) {
      Root(\.recording)

      Include(\.membership) {
        Recording.members
          .where(
            RecordingMember.user
              == .currentUser
          )
          .one()
      }

      Include(\.primaryTranscript) {
        Recording.transcriptions
          .where(
            Transcription.isPrimary == true
          )
          .one()
      }

      Include(\.preview) {
        Recording.transcriptPreview
      }
    }
  }
}
```

## Rename Command

A command is the mutation counterpart to a query value. The macro can
derive the Instant mutations, the optimistic local change envelope, and
the server-accepted event. The screen still decides which side effects
to run for this tap.

```swift
import InstantSwiftData

@InstantCommand
struct RenameRecording {
  var id:
    InstantID<Recording>
  var title: String

  static var mutation:
    some InstantMutationPlan<Self> {
    Update(Recording.self, id: \.id) {
      Set(Recording.title, \.title)
    }
  }
}
```
