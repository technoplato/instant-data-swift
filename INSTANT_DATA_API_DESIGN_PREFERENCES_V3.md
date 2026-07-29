# Instant Data API Design Preferences, Version 3

This is the V3 working draft for the SwiftUI-facing Instant API. It records
design targets, not a complete inventory of symbols available in the package
today. Before copying an example into production code, confirm it against
`Sources/` and a compiling fixture in `Tests/`; those are authoritative for
currently usable syntax.

The accepted ownership and local-first semantics are recorded in
`docs/adr/0001-application-sync-boundary.md`. This document illustrates that
boundary; it does not create a second synchronization architecture.

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
- Current `Sources/` declarations and compiling fixture tests take precedence
  when a sketch differs from the implementation.
- Projection/fetch-builder names such as `@InstantProjectionBuilder`,
  `@InstantFetchBuilder`, `InstantFetchPlan`, `Project`, `Query`, and `Count`
  may be aspirational and must not be presented as implemented without a
  source check.
- The recordings-list, auth-login, recording, and playback room/presence/topic
  public seams now have compiling fixtures and lifecycle tests. Their recorded
  syntax is the implementation baseline, not an open-ended sketch.
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
  shows SQLiteData's count shape. The implemented Instant adaptation uses an
  `@Fetch` request that projects rows into a count:

  ```swift
  struct ReminderCountRequest: InstantFetchKeyRequest {
    var fetchRequest: InstantFetchRequest<Int> {
      InstantFetchRequest(Reminder.query) { $0.count }
    }
  }

  @Fetch(ReminderCountRequest())
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
- An optional or single entity declares state with `@FetchOne`.
- An aggregate, count, or composite value declares state with `@Fetch` and an
  `InstantFetchRequest` that projects entity rows into that value.
- Static fetch declarations observe automatically; they do not require a task,
  `load`, or subscribe call.
- Dynamic input replaces the wrapper-owned key and observation.
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

## Application Boundary

Apps know schema, query shape, observation lifetime, dynamic inputs, mutations,
auth, and sharing. Normal features do not know about local materialization,
outbox persistence, reconnect, mutation delivery, or rejected-stream recovery.
Instant Swift Data owns those mechanics.

There is no public `queryLocal`. A preview, test, CLI, or deliberately local-only
app injects a local-only `InstantSwiftDataClient` and uses ordinary fetch,
subscription, and mutation APIs. Any direct local materializer stays private to
the runtime or internal test support.

`queryOnce` remains a freshness-sensitive one-shot operation. It may reuse
applicable local data while connected, but it fails offline instead of silently
returning stale data. Local-first feature state comes from ongoing observation:
the wrapper can emit cached and optimistic values immediately, then reconcile
with live results.

Explicit flush and delivery status belong only in CLIs, diagnostics, tests, or
a real user-visible operation. Normal feature actions do not flush after writes
or coordinate reconnection.

Static declarations have no lifecycle modifier:

```swift
@FetchAll(
  Recording.query.order(.serverCreatedAt, .descending)
)
private var recordings: [Recording]

private struct ActiveRecordingCountRequest: InstantFetchKeyRequest {
  var fetchRequest: InstantFetchRequest<Int> {
    InstantFetchRequest(
      Recording.query.where(Recording.isArchived == false)
    ) { $0.count }
  }
}

@Fetch(ActiveRecordingCountRequest())
private var activeRecordingCount = 0

@Fetch(RecordingDashboard())
private var dashboard = RecordingDashboard.Value()
```

The `.instantFetch` modifier remains the canonical SwiftUI spelling when local
view input changes the query key. The feature declares the new key; the wrapper
owns cached emission, cancellation, replacement, and live observation.

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
typed conversion. The authenticated identity preserves Instant's standard
`email`, `imageURL`, `type`, and `isGuest` fields. Arbitrary application profile
fields still come from a typed `$users` query; the auth session does not pretend
that the complete user entity snapshot has been materialized.

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

The executable recording-action fixture also fixes the ownership boundary:
product recording preparation owns task replacement and drops stale callbacks;
`InstantMessage` owns the durable optimistic mutation lifecycle. The fixture
proves optimistic and accepted callbacks fire once, rejection produces
actionable recovery once, a later outbox retry does not replay call-site
effects, and accepted state survives runtime relaunch. Start creates the
canonical owner/member/recording/transcription ref graph in one message; finish
updates the recording and transcription together; attachments link through a
required recording ref. Their exact mutation and precondition shapes are
covered in `V3RecordingActionFixtureTests`, and the matching Swift-owned schema
and validation permissions are generated with `--example recording-action`.
Pinned TypeScript type-check and server installation are contract gates, not
open public-syntax questions.

## Request Objects

Request objects are available, but they are not the default shape for every
screen. The currently implemented composite surface is
`InstantFetchKeyRequest` plus `InstantFetchRequest<Value>`. The key request is
`Sendable`; it is not required to be `Hashable` unless a separate identity API,
such as SwiftUI `.task(id:)`, imposes that requirement.

Use a request when one wrapper should vend one library-owned combined value.
Its `combineLatest` observation emits only after every source has emitted; it
does not claim an atomic cross-query snapshot:

```swift
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
      Text(summary.visibleCount.formatted() + " recordings")
    }
  }
}
```

The static declaration observes automatically. `InstantFetchRequest` owns the
child-query load, subscription, and emission merge. The feature does not fetch,
subscribe to, or merge those parts itself.

A static composite request can capture a detail ID in the view initializer.
That ID is fixed for the view's lifetime:

```swift
struct RecordingDetail: Sendable, Equatable {
  var recording: VoiceTrailRecording?
  var transcriptions: [VoiceTrailTranscription] = []
}

struct RecordingDetailRequest: InstantFetchKeyRequest {
  var recordingID: InstantID<VoiceTrailRecording>

  var fetchRequest: InstantFetchRequest<RecordingDetail> {
    InstantFetchRequest(
      VoiceTrailRecording.query.where(
        VoiceTrailRecording.identifier == recordingID.rawValue
      ),
      VoiceTrailTranscription.query.where(
        VoiceTrailTranscription.recording == recordingID
      )
    ) { recordings, transcriptions in
      RecordingDetail(
        recording: recordings.first,
        transcriptions: transcriptions
      )
    }
  }
}

@Fetch private var detail: RecordingDetail

init(recordingID: InstantID<VoiceTrailRecording>) {
  _detail = Fetch(
    wrappedValue: RecordingDetail(),
    RecordingDetailRequest(recordingID: recordingID)
  )
}
```

When the identity must change without constructing a new view identity, use a
replacement API that exists in the current source. The existing composite
wrapper exposes request `load`, `subscribe`, and `task` operations; there is no
current general-purpose composite `.instantFetch` SwiftUI modifier. Do not
substitute the aspirational `@InstantFetchBuilder`/`InstantFetchPlan` sketch for
the compiling request API.

If a screen only needs rows, use `@FetchAll`. If it needs rows plus a coupled
count, use `@Fetch` with a narrowly named request such as
`RecordingListSummaryRequest`.

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

The playback screen models room identity, people currently listening, and
typed room messages with one schema:

```swift
struct ActiveRecordingRoom:
  InstantRoomSchema {
  typealias Presence =
    ActiveRecordingPresence

  enum Topic:
    String,
    InstantRoomTopic {
    typealias RoomSchema =
      ActiveRecordingRoom

    case reaction
    case commentDraft
  }
}
```

The view can join a room, read presence, and publish topic messages:

```swift
struct VoiceTrailPlaybackScreen: View {
  var recordingID:
    InstantID<Recording>

  @Room
  private var room:
    InstantRoom<ActiveRecordingRoom>

  @Presence
  private var listeners:
    [ListenerPresence]

  @Topic(
    ActiveRecordingRoom.Topic.reaction
  )
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
      InstantRoom(
        type: "recording.playback",
        id: recordingID.rawValue
      )
    )
    .presence(
      $listeners,
      in: room,
      publishing:
      ListeningPresence(
        recordingID: recordingID,
        playbackTime: currentPlaybackTime
      )
    )
    .instantTopic(
      $reactions,
      in: room
    )
  }
}
```

Presence is ephemeral: who is here and what they are doing now. Topics
are room-scoped messages: reactions, comments, cursor moves, playback
markers, and other collaborative events.

Decision, 2026-07-18: room presence uses both a wrapper and a modifier.
`@Presence` owns decoded listener state, loading/error state, observation, and
cancellation. `.presence(_:in:publishing:)` supplies the dynamic typed room and
current user's value. Observation is keyed only by room identity, while current
presence has its own encoded task identity, so playback updates publish without
restarting the listener subscription. `@Topic` owns typed topic state and
call-site publication callbacks; `.instantTopic(_:in:)` attaches it to the
matching room schema. Commits `fbc34ad`, `347154c`, and `6688a31` are the
compiling and lifecycle-tested baseline.

Decision, 2026-07-18: playback time crosses the room boundary as
`offsetSeconds: Double`; `Duration` is a product convenience computed from that
stored value. Typed `InstantID` values encode as canonical strings, so presence
uses string `userID` and optional string `focusedSegmentID` without giving up
typed IDs in Swift.

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

Entity delivery and media transfer are independent. Recording metadata, links,
and transcript projection continue through ordinary observation and mutation
delivery even when audio upload or download is slow, offline, or rejected.

The media cache should move toward a bounded LIFO policy: retain and attempt the
newest eligible media first, cap item and byte usage, evict the oldest eligible
cache entries at the bound, persist retry metadata, and isolate each rejected
media item or stream. A media failure must not block entity delivery or an
unrelated media stream.

## Open Questions

- Should `@InstantFetchBuilder` be core, macro-generated, or both?
- How much of a command's change envelope should be generated by macro?
- When the Swift toolchain supports noncopyable associated types, should
  `InstantMessage.Change` require `~Copyable`?
- Should borrowed change envelopes always expose sendable summaries?
- Should provider catalogs be generated from app configuration?
