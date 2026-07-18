# Instant Data API Design Preferences, Version 3

This is the V3 working draft for the SwiftUI-facing Instant API.

The implementation order, test gates, and Git version targets live in
`docs/v3-e2e-port-plan.md`.

It supersedes the earlier callback experiment. Auth and user-triggered
mutations should keep callbacks at the call site.
Property wrappers should own async work, loading state, cancellation,
and observation.

The current full-file sketches are:

- `screens/v3/auth-login.md`
- `screens/v3/recordings-list.md`
- `screens/v3/recording.md`
- `screens/v3/playback.md`
- `screens/v3/preferences.md`

These files all follow the call-site callback direction.

## Status

- These APIs are design targets.
- The recordings-list and auth-login public seams now have compiling fixtures
  and lifecycle tests. Their recorded syntax is the implementation baseline,
  not an open-ended sketch.
- The examples are intentionally narrow-column.
- VoiceTrail types are product code.
- Instant core should expose reusable primitives.
- Product wrappers may exist, but outside Instant core.

## SQLiteData Prior Art

V3 should follow SQLiteData's split:

- Direct wrappers are the default screen shape.
- Request objects are for one wrapper-owned composite value.
- Dynamic input does not by itself require a request object.

The upstream references to keep in view are:

- `Fetching.md:8-11`
  explains that wrapper choice is based on result shape:
  collection, single value, or multiple reads in one transaction.
  Path:
  `upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/`
  `Articles/Fetching.md`

- `Fetching.md:37-41`
  shows a normal list as:

  ```swift
  @FetchAll var reminders: [Reminder]
  ```

- `Fetching.md:154-161`
  shows a count as:

  ```swift
  @FetchOne(Reminder.count())
  var remindersCount = 0
  ```

- `Fetching.md:180-199`
  says separate wrappers are fine, but each owns a separate
  observation and transaction.

- `Fetching.md:201-239`
  introduces `FetchKeyRequest` only when multiple reads should be
  bundled into one custom value.

- `DynamicQueries.md:46-48`
  shows that changing a filter or search value should reload the
  wrapper key. It does not make a request object mandatory.
  Path:
  `upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/`
  `Articles/DynamicQueries.md`

- `DynamicQuery.swift:17`
  uses `@Fetch(Facts())` because the view reads a composite value.

- `DynamicQuery.swift:82-99`
  shows the `Facts` request with inputs and a `Value` containing rows,
  a search count, and a total count.
  Path:
  `upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift`

- `FetchKeyRequest.swift:46-51`
  is the small upstream protocol: `Hashable`, `Sendable`, one `Value`,
  and one `fetch` method.
  Path:
  `upstream/sqlite-data/Sources/SQLiteData/FetchKeyRequest.swift`

## Core Direction

The public SwiftUI layer should read like this:

- A list declares list state with `@FetchAll`.
- A single value or count declares state with `@FetchOne`.
- A composite value declares state with `@Fetch`.
- Buttons send messages from synchronous SwiftUI closures.
- Wrappers start and cancel tasks internally.
- Wrappers expose status for rendering.
- Call-site callbacks run optional side effects.
- Callback payloads carry the actual changed data.
- Rich payloads should be borrowed and noncopyable.

Lower-level Instant primitives should remain public:

- `db.queryOnce`
- `db.queryOnceDecoded`
- `db.subscribeQuery`
- `db.subscribeInfiniteQuery`
- `db.transact`
- `db.auth`
- `db.storage.uploadFile`
- `db.room`
- `db.rooms`
- `db.localID`

Those primitives matter for tools, tests, non-SwiftUI code, and
advanced flows. SwiftUI wrappers are convenience, not a closed world.

## Auth

Auth should be message-based at the call site:

```swift
struct VoiceTrailAuthLoginScreen: View {
  @InstantAuth(
    VoiceTrailUser.self,
    providers: VoiceTrailAuthProviders.self
  )
  private var auth

  @Dependency(\.analytics)
  private var analytics

  @Dependency(\.haptics)
  private var haptics

  @Dependency(\.toast)
  private var toast

  var body: some View {
    Button {
      providerButtonTapped(.google)
    } label: {
      Label(
        "Continue with Google",
        systemImage: "person.crop.circle"
      )
    }
    .disabled(auth.isBusy)
  }

  private func providerButtonTapped(
    _ provider: AuthProviderSelection
  ) {
    auth.signIn(
      provider,
      onProviderCompleted: { credential in
        analytics.track(
          .providerCredentialReceived(
            credential.providerID.rawValue
          )
        )
      },
      onSignedIn: { event in
        analytics.track(
          .signedIn(
            event.session.userID,
            provider: event.providerID.rawValue
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
}
```

Why this shape:

- The view does not create `Task`.
- The view does not store a callback policy object.
- The call site shows which side effects belong to this tap.
- Passive session restoration can update `auth.status` without running
  button-specific analytics or haptics.
- The app shell can observe `auth.status` to switch between signed-out,
  authenticating, failed, and signed-in states.

The implemented auth wrapper exposes durable session status separately from
the form/action mode:

```swift
enum InstantAuthStatus:
  Hashable,
  Sendable {
  case signedOut
  case working
  case signedIn(InstantAuthSession)
  case failed(InstantError)
}

enum InstantAuthMode:
  Hashable,
  Sendable {
  case enteringEmail
  case sendingMagicCode(email: String)
  case magicCodeSent(email: String)
  case verifyingMagicCode(email: String)
  case signingIn(providerID: InstantAuthProviderID)
}
```

`InstantAuthState` owns task replacement, cancellation, session observation,
and magic-code/provider exchange. Passive session restoration updates the
state but never replays call-site callbacks. Native and browser credential
acquisition stays injectable through `InstantAuthProviderAuthorizer`, so the
core does not pretend to own platform UI.

`@InstantAuth(User.self, ...)` also exposes `auth.user` as an
`InstantAuthUser<User>`. It derives a typed entity ID from the durable auth
session, which lets product mutations use `auth.user?.id` without stringly
typed conversion. It is deliberately an authenticated identity plus session,
not a claim that the complete `$users` entity snapshot has been queried.

## Provider Configuration

Provider IDs, client names, and presentation style should be centralized
in a handwritten catalog for V3:

```swift
enum VoiceTrailAuthProviders:
  InstantAuthProviderCatalog {
  static let apple =
    AuthProvider.apple(
      clientName: "apple-ios",
      presentation: .native
    )

  static let google =
    AuthProvider.google(
      clientName: "google-ios",
      presentation: .native
    )

  static let github =
    AuthProvider.github(
      clientName: "github-web",
      presentation: .externalBrowser
    )

  static let all = [
    apple,
    google,
    github
  ]
}
```

Catalog generation is a possible later convenience. It is not required to
continue the port and must preserve this public catalog protocol if added.

The screen can still sketch available providers with an enum, but the
real API should avoid duplicating provider IDs and client names across
login screens, settings screens, tests, and previews.

## Recording List

The recording list should start with SQLiteData's default shape:

```swift
struct VoiceTrailRecordingsListScreen: View {
  @FetchAll
  private var rows:
    [RecordingListRow]

  @State
  private var scope:
    RecordingListScope = .mine

  @State
  private var searchText = ""

  var body: some View {
    List(rows) { row in
      RecordingRow(row: row)
    }
    .searchable(text: $searchText)
    .instantFetch(
      $rows,
      rowsQuery
    )
  }

  private var rowsQuery:
    InstantQuery<RecordingListRow> {
    Recording.listRows(
      viewer: .currentUser,
      scope: scope,
      searchText: searchText
    )
  }
}
```

`rows` is wrapper-owned state. When `scope` or `searchText` changes,
`rowsQuery` changes, and the wrapper reloads and observes the new key.

There is no screen-level request object in the default example because
the screen is displaying one value: rows.

Decision, 2026-07-18: direct wrappers use the modifier spelling shown above.
`View.instantFetch(_:_:)` keys a SwiftUI task by the `InstantQuery`, while the
projected `FetchAll` value owns cached state, subscription replacement,
cancellation, and renderable errors. The compiling fixture is
`Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift`; the dynamic
lifecycle proof remains
`TypedAPITests.fetchAllDynamicQueryTaskReplacementCancelsStaleSubscription`.

## Recording Capture

The recording screen keeps audio, speech, clipboard, screenshot, and location
ownership in the product's `@VoiceTrailRecordingSession` wrapper. Instant owns
stable local IDs, live entity queries, and typed mutation delivery.

Decision, 2026-07-18: a dynamic recording query receives the recorder's current
concrete identifier:

```swift
.instantFetch(
  $segments,
  TranscriptionSegment.liveTimeline(
    transcriptionID: recorder.transcriptionID
  )
)
```

The identifier participates in `InstantQuery` identity, so a changed recording
or transcription ID replaces the stale observation. The earlier
`.session(\.recorder.transcriptionID)` sketch is not a reusable Swift query API:
the key path's root is the concrete view, which would couple a reusable entity
query to one product screen.

`@LocalID("device")` is a SwiftUI `DynamicProperty`. It starts one canonical
local-ID resolution for the view identity, preserves the runtime's concurrent
and relaunch stability guarantee, and publishes value, loading, and error
changes so the screen recomputes. Manual `load` and `task` methods remain public
for non-SwiftUI and advanced use.

The executable start-action fixture now also fixes the ownership boundary:
product recording preparation owns task replacement and drops stale callbacks;
`InstantMessage` owns the durable optimistic mutation lifecycle. The fixture
proves optimistic and accepted callbacks fire once, rejection produces
actionable recovery once, a later outbox retry does not replay call-site
effects, and accepted state survives runtime relaunch. Canonical ref-shaped
recording/member/transcription creation plus finish and attachment actions are
the next recording slice.

## Request Objects

Request objects should remain available. They are not the default shape
for every screen.

Use a request when one wrapper should vend one composite value:

```swift
struct VoiceTrailRecordingsSummaryScreen: View {
  @State
  private var scope:
    RecordingListScope = .mine

  @State
  private var searchText = ""

  @Fetch(
    RecordingListSummary(
      viewer: .currentUser,
      scope: .mine,
      searchText: ""
    )
  )
  private var summary =
    RecordingListSummary.Value()

  var body: some View {
    List(summary.rows) { row in
      RecordingRow(row: row)
    }
    .safeAreaInset(edge: .bottom) {
      Text(
        summary.visibleCount.formatted()
          + " of "
          + summary.totalCount.formatted()
          + " recordings"
      )
    }
    .instantFetch(
      $summary,
      request
    )
  }

  private var request:
    RecordingListSummary {
    RecordingListSummary(
      viewer: .currentUser,
      scope: scope,
      searchText: searchText
    )
  }
}
```

The request inputs exist because the query depends on them:

```swift
struct RecordingListSummary:
  InstantFetchRequest,
  Hashable {
  var viewer: InstantViewer
  var scope: RecordingListScope
  var searchText: String

  struct Value:
    Sendable,
    Equatable {
    var rows:
      [RecordingListRow] = []
    var visibleCount = 0
    var totalCount = 0
  }

  @InstantFetchBuilder<Value>
  var body:
    some InstantFetchPlan<Value> {
    Query(\.rows) {
      Recording.listRows(
        viewer: viewer,
        scope: scope,
        searchText: searchText
      )
    }

    Count(\.visibleCount) {
      Recording.query
        .visible(to: viewer)
        .where(scope.predicate)
        .whereSearch(searchText)
    }

    Count(\.totalCount) {
      Recording.query
        .visible(to: viewer)
    }
  }
}
```

Why each part exists:

- `viewer`, `scope`, and `searchText` are the key inputs.
- `Hashable` lets the wrapper detect when the request changed.
- `Value` is the one piece of wrapper-owned state.
- `rows`, `visibleCount`, and `totalCount` are outputs.
- The result builder lets the library derive load and observation.
- The screen reads `summary.rows` and counts directly.

What should not be here:

- No explicit `subscribe` method in the screen.
- No manual subscription merging in the screen.
- No `queryOnceDecoded` in the screen.
- No unexplained status counts unless the product has a real UI for
  them.

If a screen only needs rows, use `@FetchAll`. If it needs rows plus a
coupled count, use `@Fetch` with a narrowly named request such as
`RecordingListSummary`.

## Cleaning Up Further

The composite request can be hidden behind app code when the product
wants a denser screen:

```swift
struct VoiceTrailRecordingsListScreen: View {
  @VoiceTrailRecordingList(
    viewer: .currentUser,
    scope: .mine,
    searchText: ""
  )
  private var list

  var body: some View {
    List(list.rows) { row in
      RecordingRow(row: row)
    }
  }
}
```

That wrapper should live in VoiceTrail. Instant core should still expose
the direct primitives:

```swift
@FetchAll
private var rows:
  [RecordingListRow]

@Fetch
private var summary:
  RecordingListSummary.Value
```

This keeps Instant composable while allowing product screens to become
explosive but clean.

## Commands

Mutations should also be message-based. The screen should be able to
trigger a mutation without creating a `Task`:

```swift
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
```

The callback should receive the actual data that changed. That payload
should not be retainable when it exposes rich mutation data:

```swift
@InstantChangeEnvelope
struct RecordingRenamedChange:
  ~Copyable {
  let id:
    InstantID<Recording>
  let oldTitle: String
  let newTitle: String

  borrowing func summary()
    -> RecordingRenameSummary {
    RecordingRenameSummary(
      id: id,
      oldTitle: oldTitle,
      newTitle: newTitle
    )
  }
}
```

The full envelope is for analytics, haptics, and other immediate side
effects. If a caller needs durable data, it should project a small
sendable summary intentionally.

Implementation decision, 2026-07-18: `InstantMessage.prepare(using:)` returns
typed mutations and the corresponding change envelope. `db.send` persists the
optimistic transaction before invoking `onOptimisticCommit`, then observes the
transaction-specific durable lifecycle to invoke exactly one terminal callback.
Passive refreshes and later retries do not replay callbacks from the original
action. The public callbacks borrow the change value, and the VoiceTrail rename
fixture compiles with the spelling above.

Current toolchain boundary: Swift 6.2 rejects suppressing `Copyable` on a
protocol associated type, so the generic `InstantMessage.Change` is currently
`Sendable` and therefore Copyable even though callbacks receive it by borrowing.
Keep the explicit `summary()` projection and revisit a truly noncopyable generic
envelope when the language supports noncopyable associated types.

## Rooms, Presence, And Topics

The playback screen should be able to model people currently listening
to the active recording:

```swift
struct RecordingListeningRoom:
  InstantRoomTopic {
  var recordingID:
    InstantID<Recording>

  static var namespace =
    "recording.playback"
}
```

The view can join a room, read presence, and publish topic messages:

```swift
struct VoiceTrailPlaybackScreen: View {
  var recordingID:
    InstantID<Recording>

  @Room
  private var room:
    RecordingListeningRoom

  @Presence
  private var listeners:
    [ListenerPresence]

  @Topic("reactions")
  private var reactions:
    InstantTopic<RecordingReaction>

  var body: some View {
    VStack {
      HStack {
        ForEach(listeners) { listener in
          ListenerAvatar(listener)
        }
      }

      Button {
        reactions.publish(
          RecordingReaction(
            kind: .heart,
            position: currentPlaybackTime
          )
        )
      } label: {
        Label(
          "React",
          systemImage: "heart"
        )
      }
    }
    .instantRoom(
      $room,
      RecordingListeningRoom(
        recordingID: recordingID
      )
    )
    .presence(
      ListeningPresence(
        recordingID: recordingID,
        playbackTime: currentPlaybackTime
      )
    )
  }
}
```

Presence is ephemeral: who is here and what they are doing now. Topics
are room-scoped messages: reactions, comments, cursor moves, playback
markers, and other collaborative events.

## Local ID

Local IDs should be first-class because products need stable device,
installation, and local-draft identity before a server round trip:

```swift
struct VoiceTrailPreferencesScreen: View {
  @LocalID("device")
  private var deviceID

  var body: some View {
    LabeledContent(
      "Device",
      value: deviceID ?? "Loading"
    )
  }
}
```

`db.localID` should also remain public for non-SwiftUI code.

## Storage

Storage should push file deletion and download URL lookup through file
queries, not ad hoc URL APIs:

```swift
@FetchOne
private var audioFile:
  InstantFile<RecordingAudioPath>?

private func deleteAudioButtonTapped() {
  db.send(
    DeleteRecordingAudio(
      recordingID: recordingID
    ),
    onOptimisticCommit: { change in
      analytics.track(
        .audioDeleted(change.recordingID)
      )
    }
  )
}
```

Queryable file metadata stays in the data model. Temporary URLs are an
implementation detail of storage resolution.

## Open Questions

- Should `@InstantFetchBuilder` be core, macro-generated, or both?
- How much of a command's change envelope should be generated by macro?
- When the Swift toolchain supports noncopyable associated types, should
  `InstantMessage.Change` require `~Copyable`?
- Should borrowed change envelopes always expose sendable summaries?
- Should room presence be a wrapper, a modifier, or both?
- Should provider catalogs be generated from app configuration?
